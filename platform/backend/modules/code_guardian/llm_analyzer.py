import json
import logging

from config import settings

logger = logging.getLogger(__name__)

SECURITY_ANALYSIS_PROMPT = """You are a code security expert. Analyze the following {language} code for ALL security vulnerabilities.

Return a JSON object with this exact structure:
{{
  "vulnerabilities": [
    {{
      "type": "category_snake_case",
      "title": "short Chinese title",
      "riskLevel": "high|medium|low",
      "line": line_number_or_null,
      "reason": "detailed explanation in Chinese",
      "suggestion": "actionable fix advice in Chinese"
    }}
  ],
  "summary": "overall assessment in one Chinese sentence",
  "overall_risk": "high|medium|low"
}}

Rules:
- Check for: hardcoded secrets (API keys, tokens, passwords), SQL/NoSQL injection, command injection, path traversal, SSRF, XXE, deserialization (pickle, yaml unsafe load), sensitive logging, weak crypto (MD5, SHA1, DES, ECB, Math.random), dangerous config (debug=True, CORS *, verify=False, SSL disabled), XSS, IDOR, authorization bypass, race conditions, input validation gaps, insecure dependencies, hardcoded internal IPs/URLs
- riskLevel: "high" for secrets/injection/RCE/SSRF/auth_bypass. "medium" for weak_crypto/sensitive_logging/dangerous_config. "low" for minor style/config concerns.
- line: the line number where the issue is found. If the issue spans multiple lines, use the starting line. If unclear, use null.
- DO NOT flag comments or string literals as vulnerabilities unless they actually execute.
- If NO vulnerabilities found, return empty array and "low" risk.
- Only return the JSON, no markdown or explanation.

Code ({language}):
```{language}
{code}
```"""


def _call_deepseek(code: str, language: str) -> tuple[dict, str | None]:
    """Call DeepSeek and return (result, error).

    ``error`` is a user-facing Chinese message when the call could not produce a
    usable answer (network/parse/token-truncation). It stays ``None`` when the
    model replied successfully, even if it reported zero vulnerabilities.
    """
    empty = {"vulnerabilities": [], "summary": "", "overall_risk": "low"}
    if not settings.deepseek_enabled or not settings.deepseek_api_key:
        logger.warning("DeepSeek API disabled or missing API key, falling back to local rules")
        return empty, "DeepSeek 联网增强未启用，当前仅显示本地规则检测结果。"

    try:
        from openai import OpenAI
    except ImportError:
        logger.warning("openai package not installed, falling back to local rules")
        return empty, "服务器缺少 openai 依赖，无法进行 DeepSeek 联网分析。"

    prompt = SECURITY_ANALYSIS_PROMPT.format(language=language, code=code)

    try:
        client = OpenAI(api_key=settings.deepseek_api_key, base_url=settings.deepseek_api_base)

        response = client.chat.completions.create(
            model=settings.deepseek_model,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            max_tokens=8192,
            temperature=0.1,
        )

        choice = response.choices[0]
        content = choice.message.content
        if not content:
            if getattr(choice, "finish_reason", None) == "length":
                logger.error("DeepSeek response truncated by token limit for %s code", language)
                return empty, "DeepSeek 返回内容超出长度限制，请缩短代码后重试。"
            logger.error("DeepSeek returned empty content (finish_reason=%s)", getattr(choice, "finish_reason", None))
            return empty, "DeepSeek 未返回有效内容，已回退本地规则检测结果。"

        result = json.loads(content)
        logger.debug(
            "DeepSeek analyzed %d chars of %s code in %d tokens",
            len(code),
            language,
            response.usage.total_tokens if response.usage else 0,
        )
        return result, None
    except json.JSONDecodeError:
        logger.error("Failed to parse DeepSeek response as JSON")
        return empty, "DeepSeek 返回结果解析失败，已回退本地规则检测结果。"
    except Exception as exc:
        logger.error("DeepSeek API call failed: %s", exc)
        return empty, "DeepSeek API 调用失败，请检查网络或 API 配置。"


def _normalize_findings(raw_vulns: list[dict]) -> list[dict]:
    findings: list[dict] = []
    for idx, item in enumerate(raw_vulns, start=1):
        risk = str(item.get("riskLevel", "medium")).strip().lower()
        if risk not in {"high", "medium", "low"}:
            risk = "medium"
        line = item.get("line")
        if line is not None:
            try:
                line = int(line)
            except (TypeError, ValueError):
                line = None
        findings.append({
            "id": f"deepseek_{idx:03d}",
            "type": str(item.get("type", "unknown")).strip(),
            "title": str(item.get("title", "安全问题")).strip(),
            "riskLevel": risk,
            "line": line,
            "snippet": str(item.get("reason", ""))[:240],
            "reason": str(item.get("reason", "")).strip(),
            "suggestion": str(item.get("suggestion", "请修复此安全问题。")).strip(),
            "source": "deepseek",
        })
    return findings


def analyze_with_deepseek(code: str, language: str) -> tuple[list[dict], str | None]:
    """Return (findings, error). ``error`` is ``None`` on a successful call even
    when DeepSeek reports zero vulnerabilities."""
    result, error = _call_deepseek(code, language)
    vulnerabilities = result.get("vulnerabilities", [])
    findings = _normalize_findings(vulnerabilities) if vulnerabilities else []
    return findings, error
