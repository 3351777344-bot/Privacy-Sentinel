import re
from dataclasses import dataclass
from typing import Pattern


@dataclass(frozen=True)
class CodeRule:
    id: str
    type: str
    title: str
    risk_level: str
    patterns: tuple[Pattern[str], ...]
    reason: str
    suggestion: str
    languages: tuple[str, ...] = ()


def _compile(pattern: str) -> Pattern[str]:
    return re.compile(pattern, re.IGNORECASE)


CODE_RULES = [
    CodeRule(
        id="code_001",
        type="hardcoded_secret",
        title="疑似硬编码密钥",
        risk_level="high",
        patterns=(
            _compile(r"\b(api[_-]?key|secret|token|password|access[_-]?key)\b\s*[:=]\s*(?:\(\s*)?['\"][^'\"]{6,}['\"]"),
            _compile(r"sk-[A-Za-z0-9_\-]{12,}"),
            _compile(r"AKIA[0-9A-Z]{12,}"),
            _compile(r"-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----"),
        ),
        reason="代码中疑似直接写入密钥、口令或私钥，提交后可能导致凭据泄露。",
        suggestion="使用环境变量、密钥管理服务或未提交的本地配置文件保存敏感凭据。",
    ),
    CodeRule(
        id="code_002",
        type="sql_injection",
        title="SQL 拼接注入风险",
        risk_level="high",
        patterns=(
            _compile(r"(select|insert|update|delete).*(\+|%\s*\(|format\(|\$\{|f['\"]).*(where|from|into|set)?"),
            _compile(r"where\s+\w+\s*=\s*['\"]?\s*\+\s*\w+"),
            _compile(r"Statement\s+\w+.*execute(Query|Update)?\s*\([^)]*\+"),
        ),
        reason="SQL 语句疑似由用户输入直接拼接，攻击者可能构造输入改变查询逻辑。",
        suggestion="使用参数化查询、PreparedStatement 或 ORM 参数绑定，不要直接拼接 SQL。",
    ),
    CodeRule(
        id="code_003",
        type="command_execution",
        title="命令执行风险",
        risk_level="high",
        patterns=(
            _compile(r"\bos\.system\s*\("),
            _compile(r"subprocess\.(call|run|Popen)\s*\([^)]*shell\s*=\s*True"),
            _compile(r"Runtime\.getRuntime\(\)\.exec\s*\("),
            _compile(r"child_process\.exec\s*\("),
        ),
        reason="代码存在直接执行系统命令的行为，若参数来自外部输入可能造成命令注入。",
        suggestion="避免直接执行用户输入；优先使用参数数组、白名单命令和严格参数校验。",
    ),
    CodeRule(
        id="code_004",
        type="path_traversal",
        title="路径穿越风险",
        risk_level="medium",
        patterns=(
            _compile(r"\.\./"),
            _compile(r"\bopen\s*\(\s*(filename|path|file_path|request\.|req\.)"),
            _compile(r"readFile\s*\(\s*(req\.|request\.|path|filename)"),
        ),
        reason="文件路径可能由外部输入直接控制，攻击者可能访问预期目录之外的文件。",
        suggestion="限制可访问目录，规范化路径，并校验文件名与扩展名。",
    ),
    CodeRule(
        id="code_005",
        type="weak_crypto",
        title="弱加密或弱随机",
        risk_level="medium",
        patterns=(
            _compile(r"\b(md5|sha1)\s*\("),
            _compile(r"\bDES\b|AES/ECB|ECB\s*\)"),
            _compile(r"\bRandom\s*\(\s*\)|Math\.random\s*\("),
        ),
        reason="代码使用了不推荐的摘要、加密模式或随机数生成方式。",
        suggestion="使用 SHA-256、bcrypt、PBKDF2、AES-GCM、SecureRandom 等更安全方案。",
    ),
    CodeRule(
        id="code_006",
        type="sensitive_logging",
        title="敏感信息日志输出",
        risk_level="medium",
        patterns=(
            _compile(r"(print|console\.log|logger\.(info|debug|warning|error)|System\.out\.println)\s*\([^)]*(password|token|secret|api[_-]?key)"),
        ),
        reason="日志中可能输出密码、token 或密钥等敏感信息，日志扩散后会增加泄露风险。",
        suggestion="日志中不要输出密码、token、身份证号、手机号、密钥等敏感信息。",
    ),
    CodeRule(
        id="code_007",
        type="dangerous_config",
        title="危险运行配置",
        risk_level="medium",
        patterns=(
            _compile(r"debug\s*=\s*True"),
            _compile(r"allow_origins\s*=\s*\[\s*['\"]\*['\"]\s*\]"),
            _compile(r"cors.*\*"),
            _compile(r"verify\s*=\s*False"),
            _compile(r"ssl.*(disabled|false|off)"),
        ),
        reason="调试、CORS 或证书校验配置过于宽松，生产环境可能扩大攻击面。",
        suggestion="生产环境关闭 debug，限制 CORS 来源，并启用证书校验。",
    ),
    CodeRule(
        id="code_008",
        type="xss_risk",
        title="XSS 风险",
        risk_level="medium",
        patterns=(
            _compile(r"innerHTML\s*="),
            _compile(r"dangerouslySetInnerHTML"),
            _compile(r"document\.write\s*\("),
        ),
        reason="前端代码可能直接插入未过滤内容，存在跨站脚本风险。",
        suggestion="避免直接插入未过滤的用户输入，进行转义或白名单过滤。",
        languages=("javascript", "typescript"),
    ),
]


def iter_findings(code: str, language: str) -> list[dict]:
    findings: list[dict] = []
    lines = code.splitlines()
    flattened_code = code.replace("\n", " ")
    for rule in CODE_RULES:
        if rule.languages and language not in rule.languages:
            continue
        candidates: list[re.Match[str]] = []
        for pattern in rule.patterns:
            for search_text in (code, flattened_code):
                for match in pattern.finditer(search_text):
                    original_segment = code[match.start() : match.end()]
                    if original_segment.count("\n") <= 4:
                        candidates.append(match)
                        break
        if not candidates:
            continue
        match = min(candidates, key=lambda item: item.start())
        line_number = code.count("\n", 0, match.start()) + 1
        snippet = "\n".join(lines[line_number - 1 : line_number + 4]).strip()[:240]
        findings.append(
            {
                "id": f"{rule.id}_{line_number}",
                "type": rule.type,
                "title": rule.title,
                "riskLevel": rule.risk_level,
                "line": line_number,
                "snippet": snippet,
                "reason": rule.reason,
                "suggestion": rule.suggestion,
            }
        )
    return findings
