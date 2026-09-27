"""Run Doc Shield's online requirement analysis against the configured model.

This is the check that unit tests cannot make: the prompt in
``detector/doc_intent.py`` asks a real model to read a real brief, and only a
real answer shows whether the wording, the JSON shape and the training data line
up. The pytest suite injects canned payloads, so it verifies the policy around
the call, never the prompt.

Read-only by design: it never touches the API, the history store or the network
beyond the configured model endpoint, and it prints exactly what the model said
next to what the rule parser read, so a bad answer is obvious rather than
plausible.

Usage (no model needed to see the fallback behaviour):

    python tools/doc-intent-check.py --brief platform/samples/doc-risky/requirement.txt \
        --file platform/samples/doc-risky/course-paper.txt

    python tools/doc-intent-check.py --brief "把要求原文直接写在命令行" --file 报告.docx

Real credentials come from ``platform/.env`` (or the environment), the same way
the backend reads them. With the model disabled or unreachable the tool exits 0
and shows the local fallback — that is a supported outcome, not a failure.
Exit code 1 means the model answered but the answer was unusable.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from types import SimpleNamespace

REPO_ROOT = Path(__file__).resolve().parent.parent
BACKEND = REPO_ROOT / "platform" / "backend"
sys.path.insert(0, str(BACKEND))

from config import settings  # noqa: E402
from detector.doc_intent import (  # noqa: E402
    judge_content_online,
    merge_with_local,
    parse_requirement_online,
)
from modules.doc_shield.file_extractor import extract_file  # noqa: E402
from modules.doc_shield.requirement_parser import parse_requirement  # noqa: E402


def load_brief(value: str) -> str:
    candidate = Path(value)
    if candidate.is_file():
        return candidate.read_text(encoding="utf-8")
    return value


def load_files(paths: list[str]) -> list:
    files = []
    for raw in paths:
        path = Path(raw)
        if not path.is_file():
            raise SystemExit(f"找不到材料文件：{path}")
        files.append(extract_file(path.name, None, path.read_bytes()))
    return files


def show_local(brief: str, files: list) -> dict:
    parsed = parse_requirement(brief)
    print("\n===== 本地规则解析 =====")
    for key in ("formats", "namingRule", "requiredMaterials", "lengthRequirement", "deadline"):
        print(f"  {key:20} {parsed[key]}")
    print(f"  {'可解析文本':20} " + ", ".join(f"{f.fileName}={f.wordCount}字" for f in files))
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--brief", required=True, help="提交要求原文，或包含原文的文件路径")
    parser.add_argument("--file", action="append", default=[], help="材料文件路径，可重复")
    parser.add_argument("--expect-field", action="append", default=[], help="断言模型必须抽出的字段名，可重复")
    parser.add_argument("--enable", action="store_true", help="强制开启联网解析（供本地桩/联调使用）")
    parser.add_argument("--base", default="", help="覆盖模型 API 地址，例如指向本地桩服务")
    parser.add_argument("--key", default="", help="覆盖 API 密钥，仅用于联调")
    parser.add_argument("--model", default="", help="覆盖模型名")
    args = parser.parse_args()

    brief = load_brief(args.brief).strip()
    if not brief:
        raise SystemExit("提交要求为空。")
    files = load_files(args.file)

    # `active` is the settings object both entry points take, so an override is
    # a settings-shaped namespace rather than a monkeypatch of the singleton.
    active = SimpleNamespace(
        deepseek_enabled=True,
        deepseek_api_key=args.key or settings.deepseek_api_key,
        deepseek_api_base=args.base or settings.deepseek_api_base,
        deepseek_model=args.model or settings.deepseek_model,
        deepseek_timeout_seconds=settings.deepseek_timeout_seconds,
        doc_content_chars_per_file=settings.doc_content_chars_per_file,
        doc_content_chars_total=settings.doc_content_chars_total,
    )

    print(f"模型：enabled={settings.deepseek_enabled or args.enable} model={active.deepseek_model} base={active.deepseek_api_base}")
    print(f"密钥：{'已配置' if active.deepseek_api_key else '未配置'}")
    print(f"要求原文（{len(brief)} 字）：{brief[:200]}{'…' if len(brief) > 200 else ''}")

    local = show_local(brief, files)

    # Same gate the route applies before it reaches the model. Without it this
    # tool would post to the provider with an empty key, get a 401, and report a
    # misleading "online analysis failed" for a deployment that simply has the
    # feature switched off — and it would spend a real request doing so.
    if not (settings.deepseek_enabled or args.enable) or not active.deepseek_api_key:
        print("\n===== 联网解析未启用（回退本地规则）=====")
        print("  GUARDIANHUB_DEEPSEEK_ENABLED 未开启或未配置 GUARDIANHUB_DEEPSEEK_API_KEY。")
        print("  报告会标注为本地规则解析并给出该提示；本次未向模型发出任何请求。")
        return 0

    parsed, parse_warning = parse_requirement_online(brief, active=active)
    if parsed is None:
        print(f"\n===== 联网解析不可用（回退本地规则）=====\n  {parse_warning}")
        print("\n结论：联网路径未产出结果，报告将标注为本地规则解析。")
        return 0

    print("\n===== 联网解析（模型读出的要求）=====")
    for name, value in (
        ("formats", parsed.formats),
        ("namingRule", parsed.naming_rule),
        ("requiredMaterials", parsed.required_materials),
        ("lengthRequirement", parsed.length_requirement),
        ("deadline", parsed.deadline),
    ):
        print(f"  {name:20} {value}")
    for item in parsed.content_requirements:
        print(f"  内容要求              {item}")
    if parsed.notes:
        print(f"  备注                  {parsed.notes}")

    merged, sources = merge_with_local(parsed, local, parsed.content_requirements, None)
    print(f"\n  模型提供的字段：{sources}")
    print(f"  合并后 source={merged['source']}")
    for field in ("formats", "namingRule", "requiredMaterials", "lengthRequirement", "deadline"):
        origin = "模型" if field in sources else "本地规则"
        print(f"    {field:20} {origin:6} {merged[field]}")

    verdicts, judge_warning = ([], None)
    if parsed.content_requirements:
        verdicts, judge_warning = judge_content_online(
            brief, parsed.content_requirements, files, active=active
        )
        print("\n===== 内容判定 =====")
        if not verdicts:
            print(f"  未产出结论：{judge_warning}")
        for item in verdicts:
            print(f"  [{item.status:7}] {item.risk_level:6} {item.label}")
            print(f"            {item.evidence}")
    elif files:
        print("\n===== 内容判定 =====\n  要求原文里没有内容类要求，跳过（这是正常结果）")

    problems = [field for field in args.expect_field if field not in sources]
    if problems:
        print(f"\n自检失败：模型未提供预期的字段 {problems}")
        return 1
    print("\n自检通过：模型有可用的解析结果，字段回退与来源标注均按设计工作。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
