import re
from typing import Any

from .file_extractor import ExtractedFile
from .naming_template import (
    NamingTemplate,
    check_naming,
    describe_problems,
    describe_template,
    parse_naming_template,
)


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


def _naming_check(file_name: str, naming_rule: str | None) -> dict[str, Any]:
    """Build the naming-rule check row for one file.

    Four outcomes, deliberately distinguished rather than collapsed into
    "pass": an absent rule, a rule that cannot be read as a template, a
    conforming name, and a violation. Rules such as `只要一张图片` used to pass
    every file silently; they are now reported as needing manual confirmation.
    """
    if not naming_rule:
        return {
            "category": "format",
            "label": "未指定命名规则",
            "evidence": "提交要求中没有给出命名规则，未做文件名校验。",
            "riskLevel": "low",
            "status": "pass",
        }

    template: NamingTemplate = parse_naming_template(naming_rule)
    if not template.recognised:
        return {
            "category": "format",
            "label": "命名规则需人工确认",
            "evidence": f"「{naming_rule}」无法解析为可校验的命名模板，"
                        "未做自动校验。写成 学号_姓名_课程名称 这样的分段模板才能自动校验。",
            "riskLevel": "medium",
            "status": "warning",
        }

    result = check_naming(file_name, template)
    if result.ok:
        return {
            "category": "format",
            "label": "文件命名符合要求",
            "evidence": f"{file_name}（模板 {describe_template(template)}）",
            "riskLevel": "low",
            "status": "pass",
        }

    problems = "；".join(describe_problems(result.problems, template))
    return {
        "category": "format",
        "label": "文件命名不符合要求",
        "evidence": f"{file_name}：{problems}。模板 {describe_template(template)}",
        "riskLevel": "medium",
        "status": "warning",
    }


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

        checks.append(_naming_check(file.fileName, parsed_requirements.get("namingRule")))

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
