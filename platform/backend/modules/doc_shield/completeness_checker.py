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

    return checks
