from modules.link_guard.analyzer import analyze_link


def test_bare_domain_defaults_to_https() -> None:
    result = analyze_link("example.com", "其他")
    assert result["normalizedUrl"] == "https://example.com"


def test_non_web_scheme_is_high_risk() -> None:
    result = analyze_link("javascript://alert", "其他")
    assert result["riskLevel"] == "high"
    assert result["shouldOpen"] is False


def test_private_ip_is_high_risk() -> None:
    result = analyze_link("http://127.0.0.1/admin", "其他")
    labels = {item["label"] for item in result["checks"]}
    assert "内网地址" in labels
    assert result["riskLevel"] == "high"


def test_invalid_hostname_is_high_risk() -> None:
    result = analyze_link("https://bad host.example/path", "其他")
    assert any(item["id"] == "link_000_host_format" for item in result["checks"])
    assert result["riskLevel"] == "high"
