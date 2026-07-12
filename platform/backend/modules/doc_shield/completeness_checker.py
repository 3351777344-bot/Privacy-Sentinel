import re
from datetime import datetime
from typing import Any

from .file_extractor import ExtractedFile


MATERIAL_SYNONYMS = {
    "封面": ["封面", "题目", "学院", "课程名称"],
    "摘要": ["摘要", "abstract"],
    "正文": ["正文", "引言", "一、", "1.", "研究内容"],
    "参考文献": ["参考文献", "references", "bibliography"],
    "源码": ["源码", "源代码", "代码", "src", "source"],
    "源代码": ["源码", "源代码", "代码", "src", "source"],
    "截图": ["截图", "运行截图", "界面截图", "png", "jpg", "jpeg"],
    "PPT": ["ppt", "pptx", "演示文稿", "答辩"],
    "答辩PPT": ["ppt", "pptx", "演示文稿", "答辩"],
    "报告": ["报告", "课程论文", "正文"],
    "课程论文": ["课程论文", "论文", "正文", "参考文献"],
    "附件": ["附件", "附录"],
}


def _check_length(files: list[ExtractedFile], requirement: str | None) -> list[dict[str, Any]]:
    if not requirement:
        return []
    match = re.search(r"(\d{1,5})(?:[-~至到](\d{1,5}))?(字|页|word|words|page|pages)", requirement, re.IGNORECASE)
    if not match:
        return []

    minimum = int(match.group(1))
    maximum = int(match.group(2)) if match.group(2) else None
    unit = match.group(3).lower()
    is_pages = unit in {"页", "page", "pages"}
    actual = sum((file.pageCount or 0) for file in files) if is_pages else sum(file.wordCount for file in files)
    unit_label = "页" if is_pages else "字"

    if actual < minimum:
        return [{
            "category": "completeness",
            "label": f"{unit_label}数未达到要求",
            "evidence": f"要求 {requirement}，当前可解析内容共 {actual} {unit_label}。",
            "riskLevel": "high",
            "status": "fail",
        }]
    if maximum is not None and actual > maximum:
        return [{
            "category": "completeness",
            "label": f"{unit_label}数超过要求范围",
            "evidence": f"要求 {requirement}，当前可解析内容共 {actual} {unit_label}。",
            "riskLevel": "medium",
            "status": "warning",
        }]
    return [{
        "category": "completeness",
        "label": f"{unit_label}数符合要求",
        "evidence": f"要求 {requirement}，当前可解析内容共 {actual} {unit_label}。",
        "riskLevel": "low",
        "status": "pass",
    }]


def _parse_deadline(value: str) -> datetime | None:
    normalized = value.replace("：", ":").removesuffix("之前").removesuffix("前")
    current_year = datetime.now().year
    formats = (
        ("%Y年%m月%d日%H:%M", normalized),
        ("%Y年%m月%d号%H:%M", normalized),
        ("%Y-%m-%d%H:%M", normalized),
        ("%Y/%m/%d%H:%M", normalized),
        ("%Y年%m月%d日", normalized),
        ("%Y年%m月%d号", normalized),
        ("%Y-%m-%d", normalized),
        ("%Y/%m/%d", normalized),
        ("%Y年%m月%d日%H:%M", f"{current_year}年{normalized}"),
        ("%Y年%m月%d号%H:%M", f"{current_year}年{normalized}"),
        ("%Y年%m月%d日", f"{current_year}年{normalized}"),
        ("%Y年%m月%d号", f"{current_year}年{normalized}"),
    )
    for date_format, candidate in formats:
        try:
            parsed = datetime.strptime(candidate, date_format)
            if "%H" not in date_format:
                parsed = parsed.replace(hour=23, minute=59, second=59)
            return parsed
        except ValueError:
            continue
    return None


def _check_deadline(value: str | None) -> list[dict[str, Any]]:
    if not value:
        return []
    deadline = _parse_deadline(value)
    if deadline is None:
        return [{
            "category": "completeness",
            "label": "截止时间需要人工确认",
            "evidence": f"已识别截止时间“{value}”，但无法转换为明确日期。",
            "riskLevel": "medium",
            "status": "warning",
        }]
    expired = datetime.now() > deadline
    return [{
        "category": "completeness",
        "label": "提交截止时间已过" if expired else "仍在提交期限内",
        "evidence": f"识别到截止时间：{deadline.strftime('%Y-%m-%d %H:%M')}。",
        "riskLevel": "high" if expired else "low",
        "status": "fail" if expired else "pass",
    }]


def check_completeness(files: list[ExtractedFile], parsed_requirements: dict[str, Any]) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    required_materials = parsed_requirements.get("requiredMaterials", [])
    combined_text = "\n".join(file.text for file in files).lower()
    combined_names = " ".join(file.fileName for file in files).lower()

    if not required_materials:
        checks.append(
            {
                "category": "completeness",
                "label": "未识别到明确材料清单",
                "evidence": "提交要求中没有出现封面、摘要、源码、截图等清单关键词。",
                "riskLevel": "low",
                "status": "pass",
            }
        )
        checks.extend(_check_length(files, parsed_requirements.get("lengthRequirement")))
        checks.extend(_check_deadline(parsed_requirements.get("deadline")))
        return checks

    for material in required_materials:
        keywords = MATERIAL_SYNONYMS.get(material, [material])
        found_in_text = any(keyword.lower() in combined_text for keyword in keywords)
        found_in_name = any(keyword.lower() in combined_names for keyword in keywords)

        if found_in_text or found_in_name:
            checks.append(
                {
                    "category": "completeness",
                    "label": f"已发现必要材料：{material}",
                    "evidence": "通过文件内容关键词匹配" if found_in_text else "通过文件名关键词匹配",
                    "riskLevel": "low",
                    "status": "pass",
                }
            )
        else:
            checks.append(
                {
                    "category": "completeness",
                    "label": f"可能缺少必要材料：{material}",
                    "evidence": "未在可解析文本或文件名中找到对应关键词。",
                    "riskLevel": "high" if material in {"源码", "源代码", "PPT", "答辩PPT", "截图"} else "medium",
                    "status": "fail",
                }
            )

    checks.extend(_check_length(files, parsed_requirements.get("lengthRequirement")))
    checks.extend(_check_deadline(parsed_requirements.get("deadline")))
    return checks
