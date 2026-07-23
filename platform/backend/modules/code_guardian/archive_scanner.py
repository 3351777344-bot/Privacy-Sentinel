from __future__ import annotations

import hashlib
import re
import stat
import zipfile
from collections import Counter
from dataclasses import dataclass
from io import BytesIO
from pathlib import PurePosixPath

from modules.risk_scoring import calculate_security_score, highest_risk

from .analyzer import analyze_code


SCANNABLE_EXTENSIONS = {
    ".py",
    ".java",
    ".js",
    ".jsx",
    ".ts",
    ".tsx",
    ".ets",
    ".sql",
    ".txt",
    ".json",
    ".json5",
    ".yaml",
    ".yml",
    ".xml",
    ".properties",
    ".gradle",
    ".md",
    ".html",
    ".css",
}
SCANNABLE_NAMES = {
    "package.json",
    "requirements.txt",
    "oh-package.json5",
    "build-profile.json5",
}
IGNORED_DIRECTORIES = {
    ".git",
    ".hg",
    ".svn",
    ".hvigor",
    ".idea",
    ".venv",
    "venv",
    "__pycache__",
    "node_modules",
    "oh_modules",
    "vendor",
    "dist",
    "build",
    "coverage",
}
DRIVE_PATH_RE = re.compile(r"^[A-Za-z]:")
RISK_ORDER = {"high": 3, "medium": 2, "low": 1}


@dataclass(frozen=True)
class ArchiveLimits:
    max_entries: int
    max_uncompressed_bytes: int
    max_file_bytes: int
    max_compression_ratio: int


class ArchiveValidationError(ValueError):
    pass


def _safe_path(raw_name: str) -> PurePosixPath:
    normalized = raw_name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if (
        not normalized
        or normalized.startswith("/")
        or DRIVE_PATH_RE.match(normalized)
        or any(part == ".." for part in path.parts)
    ):
        raise ArchiveValidationError(f"压缩包包含不安全路径：{raw_name}")
    return path


def _is_symlink(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0o170000
    return mode == stat.S_IFLNK


def _is_unsupported_entry(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0o170000
    return mode not in (0, stat.S_IFREG, stat.S_IFDIR)


def _is_ignored(path: PurePosixPath) -> bool:
    return any(part.lower() in IGNORED_DIRECTORIES for part in path.parts[:-1])


def _is_scannable(path: PurePosixPath) -> bool:
    name = path.name.lower()
    return (
        path.suffix.lower() in SCANNABLE_EXTENSIONS
        or name in SCANNABLE_NAMES
        or name == ".env"
        or name.startswith(".env.")
    )


def _decode_text(content: bytes) -> str | None:
    if not content or b"\x00" in content:
        return None
    for encoding in ("utf-8-sig", "utf-8", "gb18030"):
        try:
            text = content.decode(encoding)
        except UnicodeDecodeError:
            continue
        sample = text[:4096]
        if not sample:
            return ""
        printable = sum(char.isprintable() or char in "\r\n\t" for char in sample)
        if printable / len(sample) < 0.85:
            return None
        return text
    return None


def _language_for_archive_entry(path: PurePosixPath) -> str | None:
    if path.suffix.lower() == ".ets":
        return "typescript"
    return None


def _file_summary(path: str, result: dict) -> dict:
    return {
        "path": path,
        "language": result["language"],
        "riskLevel": result["riskLevel"],
        "score": result["score"],
        "vulnerabilityCount": len(result["vulnerabilities"]),
    }


def analyze_code_archive(
    content: bytes,
    filename: str,
    processing_mode: str,
    limits: ArchiveLimits,
) -> dict:
    try:
        archive = zipfile.ZipFile(BytesIO(content))
    except zipfile.BadZipFile as exc:
        raise ArchiveValidationError("项目压缩包结构无效或已经损坏。") from exc

    with archive:
        infos = archive.infolist()
        if len(infos) > limits.max_entries:
            raise ArchiveValidationError(f"项目条目过多，最多允许 {limits.max_entries} 个条目。")
        file_infos = [info for info in infos if not info.is_dir()]
        if not file_infos:
            raise ArchiveValidationError("项目压缩包为空。")

        total_uncompressed = sum(max(0, info.file_size) for info in file_infos)
        if total_uncompressed > limits.max_uncompressed_bytes:
            max_mb = limits.max_uncompressed_bytes // (1024 * 1024)
            raise ArchiveValidationError(f"项目解压后总大小超过 {max_mb} MB 限制。")

        validated: list[tuple[zipfile.ZipInfo, PurePosixPath]] = []
        seen_paths: set[str] = set()
        for info in file_infos:
            path = _safe_path(info.filename)
            normalized_path = path.as_posix().casefold()
            if normalized_path in seen_paths:
                raise ArchiveValidationError(f"压缩包包含重复路径：{path.as_posix()}")
            seen_paths.add(normalized_path)
            if info.flag_bits & 0x1:
                raise ArchiveValidationError(f"暂不支持加密文件：{path.as_posix()}")
            if _is_symlink(info):
                raise ArchiveValidationError(f"压缩包包含符号链接，拒绝处理：{path.as_posix()}")
            if _is_unsupported_entry(info):
                raise ArchiveValidationError(f"压缩包包含非普通文件，拒绝处理：{path.as_posix()}")
            if info.file_size > 0:
                ratio = info.file_size / max(1, info.compress_size)
                if ratio > limits.max_compression_ratio:
                    raise ArchiveValidationError(
                        f"文件压缩比异常，可能是解压炸弹：{path.as_posix()}"
                    )
            validated.append((info, path))

        vulnerabilities: list[dict] = []
        summaries: list[dict] = []
        language_counts: Counter[str] = Counter()
        skipped_files = 0

        for info, path in validated:
            if _is_ignored(path) or not _is_scannable(path):
                skipped_files += 1
                continue
            if info.file_size > limits.max_file_bytes:
                skipped_files += 1
                continue

            try:
                raw = archive.read(info)
            except (RuntimeError, zipfile.BadZipFile) as exc:
                raise ArchiveValidationError(f"无法读取项目文件：{path.as_posix()}") from exc
            code = _decode_text(raw)
            if code is None:
                skipped_files += 1
                continue

            path_text = path.as_posix()
            result = analyze_code(
                code=code,
                language=_language_for_archive_entry(path),
                filename=path.name,
                processing_mode="local",
            )
            language_counts[result["language"]] += 1
            summaries.append(_file_summary(path_text, result))

            path_id = hashlib.sha1(path_text.encode("utf-8")).hexdigest()[:10]
            for finding in result["vulnerabilities"]:
                item = dict(finding)
                item["id"] = f"{path_id}_{item['id']}"
                item["filePath"] = path_text
                vulnerabilities.append(item)

        if not summaries:
            raise ArchiveValidationError("压缩包中没有可扫描的文本代码文件。")

    risk_level = highest_risk([item["riskLevel"] for item in vulnerabilities])
    score = calculate_security_score([item["riskLevel"] for item in vulnerabilities])
    suggestions = list(dict.fromkeys(item["suggestion"] for item in vulnerabilities))
    if not suggestions:
        suggestions = [
            "当前项目未命中高危本地规则，提交前仍建议复核依赖、配置文件和测试数据。",
            "不要把真实账号、密钥、证书或个人信息提交到代码仓库。",
        ]

    high_count = sum(1 for item in vulnerabilities if item["riskLevel"] == "high")
    medium_count = sum(1 for item in vulnerabilities if item["riskLevel"] == "medium")
    if vulnerabilities:
        summary = (
            f"已扫描 {len(summaries)} 个项目文件，发现 {len(vulnerabilities)} 项风险，"
            f"其中 high {high_count} 项、medium {medium_count} 项。"
        )
    else:
        summary = f"已扫描 {len(summaries)} 个项目文件，当前未命中本地高危规则。"

    ranked = sorted(
        summaries,
        key=lambda item: (
            RISK_ORDER[item["riskLevel"]],
            item["vulnerabilityCount"],
            -item["score"],
        ),
        reverse=True,
    )
    primary_language = language_counts.most_common(1)[0][0] if language_counts else "other"
    warning = None
    if processing_mode == "online":
        warning = "项目 ZIP 已完成本地全量扫描；为保护项目代码，当前不会把整个压缩包发送给 DeepSeek。"

    return {
        "riskLevel": risk_level,
        "score": score,
        "summary": summary,
        "language": primary_language,
        "languageSource": "filename",
        "languageConfidence": 1.0,
        "vulnerabilities": vulnerabilities,
        "suggestions": suggestions,
        "shouldSubmit": risk_level == "low",
        "detectorSource": "rule",
        "deepseekWarning": warning,
        "scanMode": "project",
        "projectName": PurePosixPath(filename).stem,
        "totalEntries": len(infos),
        "scannedFiles": len(summaries),
        "skippedFiles": skipped_files,
        "languages": dict(sorted(language_counts.items())),
        "topRiskFiles": ranked[:5],
        "fileSummaries": ranked,
    }
