from modules.code_guardian.language_detector import detect_language


def test_explicit_language_has_priority() -> None:
    result = detect_language("def hello():\n    pass", language="java", filename="sample.py")
    assert result.language == "java"
    assert result.source == "explicit"


def test_filename_is_used_in_auto_mode() -> None:
    result = detect_language("const value = 1", language="auto", filename="sample.ts")
    assert result.language == "typescript"
    assert result.source == "filename"


def test_content_detection_covers_common_languages() -> None:
    assert detect_language("def hello():\n    return True").language == "python"
    assert detect_language("public class Demo { }").language == "java"
    assert detect_language('const name: string = "Guardian"').language == "typescript"
    assert detect_language("SELECT * FROM users WHERE id = 1").language == "sql"
