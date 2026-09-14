import re
from typing import Any

from .naming_template import classify_label


FORMAT_ALIASES = {
    "pdf": ["pdf"],
    "docx": ["docx", "word", "doc"],
    "zip": ["zip", "rar", "压缩包"],
    "png": ["png", "图片", "截图"],
    "jpg": ["jpg", "jpeg"],
    "txt": ["txt"],
    "md": ["md", "markdown"],
    "ppt": ["ppt", "pptx", "演示文稿"],
}

MATERIAL_KEYWORDS = [
    "封面",
    "摘要",
    "正文",
    "参考文献",
    "源码",
    "源代码",
    "截图",
    "PPT",
    "答辩PPT",
    "课程论文",
    "报告",
    "附件",
]

# Phrases that introduce a naming rule. Mirrors the ArkTS `extractNamingRule`
# (`services/scanners/RequirementKeywords.ets`). `文件名使用` matters because the
# bundled sample brief is written that way — without it the sample yields no
# naming rule at all and the naming check silently never runs.
NAMING_MARKERS = (
    "命名规则", "文件命名", "命名格式", "文件名格式", "命名方式", "命名要求",
    "文件名使用", "文件名须为", "文件名应为", "文件名必须", "文件名称为",
)

# Filler words stripped from the front of a captured naming rule.
NAMING_FILLERS = (
    "必须严格等于", "严格等于", "严格为", "必须为", "必须是", "须为", "应为",
    "等于", "使用", "格式为", "为", "是",
)

# Characters that always end a naming rule.
_NAMING_STOPS = ("\n", "。", "；", ";")

# Comma-like characters: they end a rule unless another field follows.
_NAMING_LIST_COMMAS = ("\uFF0C", ",")


def _strip_naming_filler(captured: str) -> str:
    out = captured.strip()
    changed = True
    while changed and out:
        changed = False
        if out[0] in (" ", ":", "：", "　"):
            out = out[1:].strip()
            changed = True
            continue
        for filler in NAMING_FILLERS:
            if out.startswith(filler):
                out = out[len(filler):].strip()
                changed = True
                break
    return out


def _index_of_any_delimiter(text: str) -> int:
    """Earliest index of any rule delimiter, `-1` when there is none."""
    found = [text.find(item) for item in _NAMING_STOPS + _NAMING_LIST_COMMAS]
    found = [index for index in found if index >= 0]
    return min(found) if found else -1


def _collect_rule(rest: str) -> str:
    """Read the rule out of everything that follows a marker.

    `。`/`；`/newline always end it. A comma ends it too — unless the chunk
    after the comma is another field label, because a brief may *list* the
    fields that way (`文件名使用学号，姓名，课程名称`). Without that look-ahead
    the rule would be read as just `学号` and every correctly named file would
    then be reported as having the wrong segment count.
    """
    remaining = rest
    kept = ""
    for _ in range(12):
        at = _index_of_any_delimiter(remaining)
        if at < 0:
            kept += remaining
            break
        delimiter = remaining[at]
        head = remaining[:at]
        if delimiter not in _NAMING_LIST_COMMAS:
            kept += head
            break
        tail = remaining[at + 1:]
        next_at = _index_of_any_delimiter(tail)
        chunk = (tail[:next_at] if next_at >= 0 else tail).strip()
        if chunk and classify_label(chunk) != "any":
            kept += head + "\uFF0C"
            remaining = tail
            continue
        kept += head
        break
    return _strip_naming_filler(kept)


def extract_naming_rule(text: str) -> str:
    """Extract the raw naming rule, `''` when the brief states none.

    Substring/scan based rather than regex based so it matches the ArkTS
    implementation, which avoids the regex features ArkTS rejects.
    """
    for marker in NAMING_MARKERS:
        at = text.find(marker)
        if at < 0:
            continue
        cleaned = _collect_rule(text[at + len(marker):])
        if cleaned:
            return cleaned

    # `按照/按/以 <...> 命名`
    by_at = max(text.rfind("按照"), text.rfind("按"), text.rfind("以"))
    if by_at >= 0:
        tail = text[by_at:]
        named = tail.find("命名")
        if named > 0:
            middle = tail[:named]
            lead = max(middle.find("按"), middle.find("以"))
            if lead >= 0:
                middle = middle[lead + 1:]
            cleaned = _strip_naming_filler(middle)
            if cleaned:
                return cleaned
    return ""


def _unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        key = item.lower()
        if key not in seen:
            seen.add(key)
            result.append(item)
    return result


def parse_requirement(requirement_text: str) -> dict[str, Any]:
    text = requirement_text.strip()
    lower_text = text.lower()

    formats: list[str] = []
    for canonical, aliases in FORMAT_ALIASES.items():
        if any(re.search(rf"(?<![a-z0-9]){re.escape(alias.lower())}(?![a-z0-9])", lower_text) for alias in aliases):
            formats.append(canonical)

    materials = [keyword for keyword in MATERIAL_KEYWORDS if keyword.lower() in lower_text]
    if "源代码" in materials and "源码" not in materials:
        materials.append("源码")
    if "答辩PPT" in materials and "PPT" not in materials:
        materials.append("PPT")

    naming_rule = extract_naming_rule(text) or None

    length_requirement = None
    length_match = re.search(
        r"((?:不少于|不低于|至少|约|控制在|限制?)\s*\d{1,5}\s*(?:[-~至到]\s*\d{1,5})?\s*(?:字|页|word|words|page|pages))",
        text,
        flags=re.IGNORECASE,
    )
    if length_match:
        length_requirement = re.sub(r"\s+", "", length_match.group(1))

    deadline = None
    deadline_patterns = [
        r"(?:截止|截至|提交时间|截止时间|deadline)\s*[:：为是]?\s*([0-9]{4}\s*[年/-]\s*[0-9]{1,2}\s*[月/-]\s*[0-9]{1,2}\s*[日号]?(?:\s*[0-9]{1,2}\s*[:：]\s*[0-9]{2})?)",
        r"([0-9]{4}\s*[年/-]\s*[0-9]{1,2}\s*[月/-]\s*[0-9]{1,2}\s*[日号]?(?:\s*[0-9]{1,2}\s*[:：]\s*[0-9]{2})?\s*(?:前|之前)?)",
        r"([0-9]{1,2}\s*月\s*[0-9]{1,2}\s*[日号](?:\s*[0-9]{1,2}\s*[:：]\s*[0-9]{2})?(?:前|之前)?)",
    ]
    for pattern in deadline_patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            deadline = re.sub(r"\s+", "", match.group(1).strip()).removesuffix("之前").removesuffix("前")
            break

    return {
        "formats": _unique(formats),
        "namingRule": naming_rule,
        "requiredMaterials": _unique(materials),
        "lengthRequirement": length_requirement,
        "deadline": deadline,
        "rawText": text,
    }
