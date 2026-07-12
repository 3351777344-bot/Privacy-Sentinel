import re
from typing import Any


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

    naming_rule = None
    naming_patterns = [
        r"(?:命名规则|文件命名|命名格式|文件名格式)\s*[:：为是]?\s*([^\n，。；;]+)",
        r"(?:按|按照|以)\s*([^\n，。；;]*(?:学号|姓名|班级|课程|论文|报告)[^\n，。；;]*)\s*(?:命名|作为文件名)",
    ]
    for pattern in naming_patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            naming_rule = match.group(1).strip(" ：，。；;")
            break

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
