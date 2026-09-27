from modules.doc_shield.completeness_checker import check_completeness
from modules.doc_shield.file_extractor import ExtractedFile
from modules.doc_shield.format_checker import check_format
from modules.doc_shield.requirement_parser import parse_requirement


def extracted_file(name: str, word_count: int = 0, page_count: int | None = None) -> ExtractedFile:
    return ExtractedFile(
        fileName=name,
        extension=name.rsplit(".", 1)[-1].lower(),
        contentType="application/octet-stream",
        size=10,
        text="正文",
        status="parsed",
        wordCount=word_count,
        pageCount=page_count,
    )


def test_requirement_parser_handles_spaced_chinese_deadline() -> None:
    parsed = parse_requirement("请于 2026 年 7 月 10 日 18:00 前提交 PDF，正文不少于 3000 字。")
    assert parsed["deadline"] == "2026年7月10日18:00"
    assert parsed["lengthRequirement"] == "不少于3000字"


def test_word_count_and_future_deadline_are_actually_checked() -> None:
    parsed = parse_requirement("正文不少于 3000 字，截止时间：2099年12月31日 18:00。")
    checks = check_completeness([extracted_file("报告.pdf", word_count=1200)], parsed)
    labels = {check["label"]: check for check in checks}
    assert labels["字数未达到要求"]["status"] == "fail"
    assert labels["仍在提交期限内"]["status"] == "pass"


def test_pptx_satisfies_ppt_requirement() -> None:
    parsed = parse_requirement("请提交答辩 PPT。")
    checks = check_format([extracted_file("答辩材料.pptx")], parsed)
    assert any(check["label"] == "已上传 ppt 格式材料" and check["status"] == "pass" for check in checks)
    assert not any(check["label"] == "文件后缀不在要求范围内" for check in checks)


def test_deadline_check_states_the_timezone_it_compared_against() -> None:
    """A verdict about "on time" is meaningless without saying in which zone.

    The server's own timezone is not the user's, and a hand-deployed host is
    often on UTC; the check reads China time explicitly and says so in the
    evidence line, so a user in a different zone can still see what it compared.
    """
    parsed = parse_requirement("截止时间：2099年12月31日 18:00。")
    checks = check_completeness([extracted_file("报告.pdf")], parsed)
    deadline_row = next(check for check in checks if check["label"] == "仍在提交期限内")
    assert "北京时间" in deadline_row["evidence"]
    assert "2099-12-31 18:00" in deadline_row["evidence"]


def test_one_minute_past_the_deadline_is_reported_as_passed(monkeypatch) -> None:
    """The boundary itself: 17:59 is on time, 18:01 is not — on the same clock.

    Both halves of the comparison read ``china_now``; stubbing it proves the
    verdict flips at the deadline rather than at some host-local equivalent.
    """
    from datetime import datetime

    from modules.doc_shield import completeness_checker

    parsed = parse_requirement("截止时间：2026年9月28日 18:00。")

    monkeypatch.setattr(completeness_checker, "china_now", lambda: datetime(2026, 9, 28, 17, 59))
    early = {c["label"] for c in completeness_checker.check_completeness([extracted_file("报告.pdf")], parsed)}
    assert "仍在提交期限内" in early

    monkeypatch.setattr(completeness_checker, "china_now", lambda: datetime(2026, 9, 28, 18, 1))
    late = {c["label"] for c in completeness_checker.check_completeness([extracted_file("报告.pdf")], parsed)}
    assert "提交截止时间已过" in late
