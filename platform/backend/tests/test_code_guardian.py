from modules.code_guardian.analyzer import analyze_code


def finding_types(result: dict) -> set[str]:
    return {item["type"] for item in result["vulnerabilities"]}


def test_multiline_command_execution_is_detected() -> None:
    code = """subprocess.run(
        user_command,
        shell=True,
    )"""
    result = analyze_code(code, "python")
    assert "command_execution" in finding_types(result)
    assert result["riskLevel"] == "high"


def test_multiline_secret_is_detected() -> None:
    code = '''password = (
        "super-secret-value"
    )'''
    result = analyze_code(code, "python")
    assert "hardcoded_secret" in finding_types(result)


def test_language_specific_xss_rule() -> None:
    code = "element.innerHTML = userInput"
    assert "xss_risk" in finding_types(analyze_code(code, "javascript"))
    assert "xss_risk" not in finding_types(analyze_code(code, "python"))


def test_auto_detection_is_exposed_in_report() -> None:
    result = analyze_code("def hello():\n    return True", "auto")
    assert result["language"] == "python"
    assert result["languageSource"] == "content"
    assert result["languageConfidence"] >= 0.5
