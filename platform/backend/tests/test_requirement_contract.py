"""Contract tests shared with the on-device checker.

`platform/contracts/requirement_cases.json` is the single source of truth for how
a naming rule is read and applied. The device implementation
(`services/scanners/NamingTemplate.ets`, `.../RequirementKeywords.ets`) asserts
the same file under Node (`tools/threat-tests/run-tests.mjs`), so a behaviour
change on either side fails the other side's tests instead of silently
diverging — which is exactly how the naming check drifted into a no-op before.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from modules.doc_shield.format_checker import _naming_check
from modules.doc_shield.naming_template import (
    check_naming,
    parse_naming_template,
)
from modules.doc_shield.requirement_parser import extract_naming_rule, parse_requirement

CONTRACT_PATH = Path(__file__).resolve().parents[2] / "contracts" / "requirement_cases.json"
CONTRACT = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))


@pytest.mark.parametrize("spec", CONTRACT["namingRuleExtract"], ids=lambda s: s["text"][:24])
def test_naming_rule_extraction(spec: dict) -> None:
    assert extract_naming_rule(spec["text"]) == spec["rule"]


@pytest.mark.parametrize("spec", CONTRACT["namingRuleExtract"], ids=lambda s: s["text"][:24])
def test_parse_requirement_uses_same_extraction(spec: dict) -> None:
    parsed = parse_requirement(spec["text"])
    assert (parsed["namingRule"] or "") == spec["rule"]


@pytest.mark.parametrize("spec", CONTRACT["namingTemplateParse"], ids=lambda s: s["rule"])
def test_naming_template_parse(spec: dict) -> None:
    template = parse_naming_template(spec["rule"])
    assert template.recognised == spec["recognised"]
    if not spec["recognised"]:
        return
    assert template.kinds == spec["kinds"], template.kinds
    assert template.separator == spec["separator"]
    assert template.extension == spec["extension"]


@pytest.mark.parametrize(
    "spec",
    CONTRACT["namingCheck"],
    ids=lambda s: f"{s['rule']}<-{s['file']}",
)
def test_naming_check(spec: dict) -> None:
    template = parse_naming_template(spec["rule"])
    result = check_naming(spec["file"], template)

    if spec.get("recognised") is False:
        assert result.checked is False
        return

    assert result.checked is True
    assert result.ok == spec["ok"], result.problems
    assert sorted(result.problems) == sorted(spec["problems"])


@pytest.mark.parametrize(
    "spec",
    CONTRACT["namingCheck"],
    ids=lambda s: f"{s['rule']}<-{s['file']}",
)
def test_check_format_rows_match_contract(spec: dict) -> None:
    """The check row reported to the UI must reflect the contract verdict."""
    row = _naming_check(spec["file"], spec["rule"])

    if spec.get("recognised") is False:
        assert row["status"] == "warning"
        assert row["label"] == "命名规则需人工确认"
        return

    assert row["status"] == ("pass" if spec["ok"] else "warning")
    assert row["label"] == ("文件命名符合要求" if spec["ok"] else "文件命名不符合要求")


def test_absent_naming_rule_is_reported_honestly() -> None:
    row = _naming_check("随便起个名.pdf", None)
    assert row["label"] == "未指定命名规则"
    assert row["status"] == "pass"


@pytest.mark.parametrize("spec", CONTRACT["formatCheck"], ids=lambda s: ",".join(s["formats"]))
def test_format_extensions_are_accepted_groups(spec: dict) -> None:
    """doc/docx, ppt/pptx and zip/rar must stay interchangeable."""
    from modules.doc_shield.format_checker import _accepted_extensions

    for required in spec["formats"]:
        accepted = _accepted_extensions(required)
        assert required in accepted


def test_sample_brief_yields_a_usable_naming_template() -> None:
    """Regression: the bundled sample brief used to produce no naming rule."""
    parsed = parse_requirement(
        "提交课程论文 PDF、封面和签字承诺书；文件名使用学号_姓名_课程名称。"
    )
    assert parsed["formats"] == ["pdf"]
    assert parsed["namingRule"] == "学号_姓名_课程名称"

    template = parse_naming_template(parsed["namingRule"])
    assert template.recognised is True
    assert template.kinds == ["studentId", "name", "course"]


def test_tightened_material_synonyms_reject_cooccurrence_terms() -> None:
    """`课程名称` must no longer satisfy a 封面 requirement."""
    from modules.doc_shield.completeness_checker import MATERIAL_SYNONYMS

    assert "课程名称" not in MATERIAL_SYNONYMS["封面"]
    assert "正文" not in MATERIAL_SYNONYMS["报告"]
