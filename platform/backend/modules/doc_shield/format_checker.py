import re
from typing import Any

from .file_extractor import ExtractedFile


BAD_NAME_PATTERNS = [
    r"最终版",
    r"终版",
    r"新建文档",
    r"未命名",
    r"无标题",
    r"副本",
    r"copy",
    r"final[_-]?final",
    r"^文档\d*$",
]

FORMAT_EXTENSION_GROUPS = {
    "docx": {"doc", "docx"},
    "ppt": {"ppt", "pptx"},
    "zip": {"zip", "rar"},
}


def _accepted_extensions(required_format: str) -> set[str]:
    return FORMAT_EXTENSION_GROUPS.get(required_format, {required_format})


def _check_naming_rule(file_name: str, naming_rule: str | None) -> tuple[bool, list[str]]:
    if not naming_rule:
        return True, []

    stem = file_name.rsplit(".", 1)[0]
    problems: list[str] = []
    if "学号" in naming_rule and not re.search(r"\d{6,}", stem):
        problems.append("缺少疑似学号")
    if "姓名" in naming_rule and not re.search(r"[\u4e00-\u9fa5]{2,}|[A-Za-z]{2,}", stem):
        problems.append("缺少疑似姓名")
    if ("-" in naming_rule or "—" in naming_rule) and "-" not in stem:
        problems.append("命名规则要求使用连字符")
    if "_" in naming_rule and "_" not in stem:
        problems.append("命名规则要求使用下划线")

    return len(problems) == 0, problems


def check_format(files: list[ExtractedFile], parsed_requirements: dict[str, Any]) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    required_formats = [item.lower() for item in parsed_requirements.get("formats", [])]
    uploaded_extensions = {file.extension.lower() for file in files if file.extension}

    if required_formats:
        for required_format in required_formats:
            accepted = _accepted_extensions(required_format)
            matched = [file.fileName for file in files if file.extension.lower() in accepted]
            if matched:
                checks.append(
                    {
                        "category": "format",
                        "label": f"已上传 {required_format} 格式材料",
                        "evidence": "、".join(matched),
                        "riskLevel": "low",
                        "status": "pass",
                    }
                )
            else:
                checks.append(
                    {
                        "category": "format",
                        "label": f"缺少 {required_format} 格式材料",
                        "evidence": f"提交要求包含 {required_format}，当前上传：{', '.join(sorted(uploaded_extensions)) or '无'}",
                        "riskLevel": "high",
                        "status": "fail",
                    }
                )

    for file in files:
        accepted_extensions = set().union(*(_accepted_extensions(item) for item in required_formats)) if required_formats else set()
        if required_formats and file.extension.lower() not in accepted_extensions:
            checks.append(
                {
                    "category": "format",
                    "label": "文件后缀不在要求范围内",
                    "evidence": f"{file.fileName} 的后缀为 .{file.extension or '无'}",
                    "riskLevel": "medium",
                    "status": "warning",
                }
            )

        stem = file.fileName.rsplit(".", 1)[0]
        if any(re.search(pattern, stem, flags=re.IGNORECASE) for pattern in BAD_NAME_PATTERNS):
            checks.append(
                {
                    "category": "format",
                    "label": "文件名存在明显临时命名",
                    "evidence": file.fileName,
                    "riskLevel": "medium",
                    "status": "warning",
                }
            )

        ok, problems = _check_naming_rule(file.fileName, parsed_requirements.get("namingRule"))
        checks.append(
            {
                "category": "format",
                "label": "文件命名规则检查",
                "evidence": file.fileName if ok else f"{file.fileName}：{'；'.join(problems)}",
                "riskLevel": "low" if ok else "medium",
                "status": "pass" if ok else "warning",
            }
        )

        if file.status == "parse_failed":
            checks.append(
                {
                    "category": "format",
                    "label": "文件内容解析失败",
                    "evidence": file.error or file.fileName,
                    "riskLevel": "medium",
                    "status": "warning",
                }
            )

    if not files:
        checks.append(
            {
                "category": "format",
                "label": "未上传材料",
                "evidence": "请至少上传一个待提交文件。",
                "riskLevel": "high",
                "status": "fail",
            }
        )

    return checks
