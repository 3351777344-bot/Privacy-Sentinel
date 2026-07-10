import re
from ipaddress import ip_address
from urllib.parse import parse_qs, urlparse


SHORT_DOMAINS = {"bit.ly", "t.cn", "tinyurl.com", "goo.gl", "ow.ly", "is.gd", "buff.ly", "shorturl.at"}
SUSPICIOUS_KEYWORDS = {"login", "verify", "auth", "pay", "bank", "wallet", "free", "gift", "bonus", "prize", "password", "reset"}
SUSPICIOUS_PARAMS = {"redirect", "token", "session", "callback", "verify", "code", "auth", "password", "pay"}
OFFICIAL_WORDS = {"official", "secure", "verify", "login"}
TRUSTED_DOMAINS = {"edu.cn", "gov.cn", "qq.com", "wechat.com", "alipay.com", "taobao.com", "jd.com"}


def normalize_url(raw_url: str) -> str:
    text = raw_url.strip()
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", text):
        return text
    return f"https://{text}"


def _check(check_id: str, label: str, status: str, risk_level: str, message: str) -> dict:
    return {"id": check_id, "label": label, "status": status, "riskLevel": risk_level, "message": message}


def _is_ip(host: str) -> bool:
    try:
        ip_address(host)
        return True
    except ValueError:
        return False


def _has_random_token(text: str) -> bool:
    return bool(re.search(r"(?=.*[A-Za-z])(?=.*\d)[A-Za-z0-9_\-]{24,}", text))


def run_url_rules(normalized_url: str) -> tuple[list[dict], list[dict]]:
    parsed = urlparse(normalized_url)
    host = (parsed.hostname or "").lower()
    query = parse_qs(parsed.query)
    checks: list[dict] = []
    suspicious_params: list[dict] = []

    if parsed.scheme not in {"http", "https"}:
        checks.append(_check("link_000", "协议合法性", "fail", "high", "仅允许检查和打开 HTTP/HTTPS 链接。"))
    if not host:
        checks.append(_check("link_000_host", "域名检查", "fail", "high", "链接缺少有效域名。"))
    if parsed.username or parsed.password:
        checks.append(_check("link_000_auth", "URL 身份信息", "fail", "high", "链接在域名前包含用户名或密码，可能用于隐藏真实域名。"))

    if parsed.scheme == "https":
        checks.append(_check("link_001", "HTTPS 检查", "pass", "low", "该链接使用 HTTPS 加密传输。"))
    else:
        checks.append(_check("link_001", "HTTPS 检查", "warning", "medium", "该链接未使用 HTTPS，传输内容可能被窃听或篡改。"))

    if host in SHORT_DOMAINS:
        checks.append(_check("link_002", "短链接检查", "warning", "medium", f"{host} 是常见短链接域名，真实落地页不可见。"))
    else:
        checks.append(_check("link_002", "短链接检查", "pass", "low", "未命中常见短链接域名。"))

    if _is_ip(host):
        checks.append(_check("link_003", "IP 地址直连", "fail", "high", "链接直接使用 IP 地址，缺少可信域名背书。"))
        try:
            if ip_address(host).is_private or ip_address(host).is_loopback:
                checks.append(_check("link_003_private", "内网地址", "fail", "high", "链接指向内网或本机地址，不应作为公开链接打开。"))
        except ValueError:
            pass

    if "xn--" in host:
        checks.append(_check("link_003_idn", "国际化域名", "warning", "medium", "域名包含 Punycode，需警惕视觉相似字符仿冒。"))

    if len(host) > 45 or host.count(".") >= 4:
        checks.append(_check("link_004", "域名结构", "warning", "medium", "域名过长或子域层级较多，可能用于混淆真实来源。"))

    if len(normalized_url) > 120:
        checks.append(_check("link_005", "URL 长度", "warning", "medium", f"URL 长度为 {len(normalized_url)}，可能隐藏跳转或追踪参数。"))

    hit_keywords = sorted(keyword for keyword in SUSPICIOUS_KEYWORDS if keyword in normalized_url.lower())
    if hit_keywords:
        checks.append(_check("link_006", "可疑关键词", "warning", "medium", f"链接包含 {', '.join(hit_keywords)} 等敏感场景词。"))

    for name in query:
        if name.lower() in SUSPICIOUS_PARAMS:
            suspicious_params.append(
                {
                    "name": name,
                    "riskLevel": "medium",
                    "reason": f"{name} 参数可能携带跳转、身份、验证或支付相关信息。",
                }
            )
    if suspicious_params:
        names = "、".join(item["name"] for item in suspicious_params)
        checks.append(_check("link_007", "可疑参数", "warning", "medium", f"链接包含 {names} 参数，建议谨慎处理。"))

    if _has_random_token(parsed.path) or _has_random_token(parsed.query):
        checks.append(_check("link_008", "随机字符串", "warning", "medium", "链接中包含较长随机 token，可能用于追踪、验证或一次性跳转。"))

    trusted = any(host == domain or host.endswith(f".{domain}") for domain in TRUSTED_DOMAINS)
    contains_official_word = any(word in host for word in OFFICIAL_WORDS)
    if contains_official_word and not trusted:
        checks.append(_check("link_009", "仿冒官方域名", "warning", "medium", "域名含 official、secure、verify 或 login 等伪官方词，但不属于常见可信域名。"))

    if not checks:
        checks.append(_check("link_010", "基础结构", "pass", "low", "未发现明显结构风险。"))

    return checks, suspicious_params
