"""Ordered naming-rule templates — Python mirror of the on-device checker.

The device parses the same rule from the same brief text (the naming check needs
only the file name, so it runs locally with no upload). This module and
`platform/harmony/entry/src/main/ets/services/scanners/NamingTemplate.ets` must
produce identical verdicts; both are pinned by
`platform/contracts/requirement_cases.json` and both test suites read that file.

Two portability details worth keeping in mind when editing:

* `[0-9]` is used instead of `\\d` because Python's `\\d` also matches
  non-ASCII digits while JavaScript's does not.
* Everything is substring/scan based rather than regex-splitting, to match the
  ArkTS implementation that deliberately avoids regex features ArkTS rejects.

Two rules of thumb, mirrored from the ArkTS side:

* A rule may *list* its fields (`学号、姓名、课程名称`). List punctuation splits
  the rule into fields but is never demanded back in the file name.
* The rule side is lenient about stray separators, the file-name side is not —
  `_2024001_张三.pdf` is reported, not silently accepted.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

KNOWN_EXTENSIONS = {
    "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx",
    "txt", "md", "zip", "rar", "7z", "png", "jpg", "jpeg",
}

# Separators accepted inside a file name. Only these can become the separator a
# template demands, because only these can legitimately appear in a file name.
FILE_SEPARATORS = ("_", "-", "\u2014", "\uFF0D")

# Separators that additionally delimit fields when a rule *lists* them, e.g.
# `学号、姓名、课程名称`. They split the rule into fields but never become the
# demanded separator — nobody writes `2024001、张三、数据结构.pdf`.
LIST_SEPARATORS = ("\u3001", "\uFF0C", ",", "+")

# Ordered label -> kind table. Order matters: `课程名称` must be tested before
# any generic `课程`.
KIND_RULES: list[tuple[tuple[str, ...], str]] = [
    (("课程名称", "课程名", "课名", "课程"), "course"),
    (("学号",), "studentId"),
    (("姓名", "名字"), "name"),
    (("班级", "班号"), "class"),
    (("专业",), "major"),
    (("学院",), "college"),
    (("论文题目", "论文名", "题目", "标题"), "title"),
    (("日期",), "date"),
    (("序号", "编号", "版本"), "serial"),
]

KIND_LABELS = {
    "studentId": "学号",
    "name": "姓名",
    "course": "课程名称",
    "class": "班级",
    "major": "专业",
    "college": "学院",
    "title": "题目",
    "date": "日期",
    "serial": "序号",
    "any": "内容",
}


@dataclass
class NamingTemplate:
    recognised: bool
    separator: str = ""
    kinds: list[str] = field(default_factory=list)
    extension: str = ""
    labels: list[str] = field(default_factory=list)


@dataclass
class NamingCheckResult:
    checked: bool
    ok: bool
    problems: list[str] = field(default_factory=list)


def extension_of(file_name: str) -> str:
    dot = file_name.rfind(".")
    if dot <= 0 or dot == len(file_name) - 1:
        return ""
    return file_name[dot + 1:].lower()


def stem_of(file_name: str) -> str:
    ext = extension_of(file_name)
    if not ext:
        return file_name
    return file_name[: len(file_name) - len(ext) - 1]


def is_file_separator(ch: str) -> bool:
    """True when `ch` may be demanded as the separator of a file name."""
    return ch in FILE_SEPARATORS


def is_separator(ch: str) -> bool:
    """True when `ch` splits fields in a rule or in a file name."""
    return is_file_separator(ch) or ch in LIST_SEPARATORS


def split_segments(text: str) -> list[str]:
    """Split on any separator run, dropping empties (`a__b` -> `a`, `b`).

    Dropping is right for the *rule* side — a brief may end with punctuation
    (`..._课程名称。`) — but it also means a stray separator in a file name would
    vanish, so `check_naming` flags those separately via `_has_empty_segment`.
    """
    out: list[str] = []
    current = ""
    for ch in text:
        if is_separator(ch):
            if current:
                out.append(current)
                current = ""
        else:
            current += ch
    if current:
        out.append(current)
    return out


def separators_in(text: str) -> list[str]:
    """Every *file-name* separator in `text`, in order.

    Deliberately narrower than `is_separator`: a rule written as a list
    (`学号、姓名、课程名称`) must not end up demanding `、` in the file name.
    """
    return [ch for ch in text if is_file_separator(ch)]


def dominant_separator(found: list[str]) -> str:
    if not found:
        return ""
    best = found[0]
    best_count = 0
    for candidate in found:
        count = found.count(candidate)
        if count > best_count:
            best_count = count
            best = candidate
    return best


def classify_label(label: str) -> str:
    lower = label.strip().lower()
    for needles, kind in KIND_RULES:
        if any(needle in lower for needle in needles):
            return kind
    return "any"


def is_all_digits(text: str) -> bool:
    if not text:
        return False
    return all("0" <= ch <= "9" for ch in text)


def parse_naming_template(rule: str) -> NamingTemplate:
    """Read a naming rule as an ordered template.

    A rule is a template when it has two or more segments, or one segment whose
    label names a concrete field. Prose like `只要一张图片` is reported as
    unrecognised so callers can ask for manual confirmation instead of silently
    passing every file.
    """
    trimmed = (rule or "").strip()
    body = trimmed
    extension = ""

    dot = trimmed.rfind(".")
    if dot > 0:
        tail = trimmed[dot + 1:].lower()
        if tail in KNOWN_EXTENSIONS:
            extension = tail
            body = trimmed[:dot]

    labels = split_segments(body)
    separator = dominant_separator(separators_in(body))
    kinds = [classify_label(label) for label in labels]
    recognised = len(labels) >= 2 or any(kind != "any" for kind in kinds)

    if not recognised:
        return NamingTemplate(recognised=False)
    return NamingTemplate(
        recognised=True,
        separator=separator,
        kinds=kinds,
        extension=extension,
        labels=labels,
    )


def matches_kind(segment: str, kind: str) -> bool:
    value = segment.strip()
    if not value:
        return False
    if kind == "any":
        return True
    if kind == "studentId":
        return re.fullmatch(r"[0-9]{6,20}", value) is not None
    if kind == "name":
        if re.fullmatch(r"[\u4e00-\u9fa5\u00b7]{2,8}", value):
            return True
        return re.fullmatch(r"[A-Za-z][A-Za-z .'-]{1,29}", value) is not None
    if kind == "class":
        return re.fullmatch(r"[\u4e00-\u9fa5A-Za-z0-9]{2,20}", value) is not None
    if kind == "date":
        if re.fullmatch(r"[0-9]{4}[-./]?[0-9]{2}[-./]?[0-9]{2}", value):
            return True
        return re.fullmatch(r"[0-9]{6,8}", value) is not None
    if kind == "serial":
        return re.fullmatch(r"[A-Za-z0-9]{1,20}", value) is not None
    # course / title / major / college: free text, but a bare number is not a name.
    return not is_all_digits(value)


def _has_empty_segment(stem: str) -> bool:
    """True when `stem` has an empty field — a leading, trailing or doubled
    separator, e.g. `_2024001_张三.pdf` or `2024001__张三.pdf`.

    Without this the stray separator disappears in `split_segments` and the name
    is reported as compliant — the same class of false pass the ordered
    template was introduced to remove.
    """
    if not stem:
        return False
    if is_separator(stem[0]) or is_separator(stem[-1]):
        return True
    return any(
        is_separator(stem[i]) and is_separator(stem[i - 1])
        for i in range(1, len(stem))
    )


def check_naming(file_name: str, template: NamingTemplate) -> NamingCheckResult:
    """Judge a filename against a parsed template.

    Problem codes are stable so the shared contract can assert them:
    `empty-segment`, `segment-count`, `field:<kind>`, `separator`, `extension`.

    `empty-segment` and `segment-count` are mutually exclusive: when a separator
    is stray the segment count is off for a reason already reported.
    """
    if not template.recognised:
        return NamingCheckResult(checked=False, ok=True)

    actual_extension = extension_of(file_name)
    stem = stem_of(file_name)
    parts = split_segments(stem)
    problems: list[str] = []

    if _has_empty_segment(stem):
        problems.append("empty-segment")
    elif len(parts) != len(template.kinds):
        problems.append("segment-count")
    else:
        for part, kind in zip(parts, template.kinds):
            if not matches_kind(part, kind):
                problems.append(f"field:{kind}")

    if template.separator and template.separator not in stem:
        problems.append("separator")
    if template.extension and actual_extension != template.extension:
        problems.append("extension")

    return NamingCheckResult(checked=True, ok=not problems, problems=problems)


def describe_template(template: NamingTemplate) -> str:
    if not template.recognised:
        return ""
    sep = template.separator or "无分隔符"
    ext = f"，扩展名 .{template.extension}" if template.extension else ""
    joined = (template.separator or "_").join(template.labels)
    return f"{joined}（{len(template.kinds)} 段，分隔符 {sep}{ext}）"


def describe_problems(problems: list[str], template: NamingTemplate) -> list[str]:
    out: list[str] = []
    joined = (template.separator or "_").join(template.labels)
    for code in problems:
        if code == "segment-count":
            out.append(f"命名应有 {len(template.kinds)} 段（{joined}），实际段数不符")
        elif code == "empty-segment":
            out.append("分隔符使用有误（出现了多余、连续或首尾分隔符）")
        elif code == "separator":
            out.append(f"命名规则要求使用「{template.separator}」作为分隔符")
        elif code == "extension":
            out.append(f"扩展名应为 .{template.extension}")
        elif code.startswith("field:"):
            kind = code[len("field:"):]
            out.append(f"{KIND_LABELS.get(kind, '内容')}段格式不符")
        else:
            out.append(code)
    return out
