from __future__ import annotations

import stat
import zipfile
from io import BytesIO

import pytest

from modules.code_guardian.archive_scanner import (
    ArchiveLimits,
    ArchiveValidationError,
    analyze_code_archive,
)


DEFAULT_LIMITS = ArchiveLimits(
    max_entries=20,
    max_uncompressed_bytes=1024 * 1024,
    max_file_bytes=128 * 1024,
    max_compression_ratio=100,
)


def build_zip(files: dict[str, bytes | str], compression: int = zipfile.ZIP_DEFLATED) -> bytes:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=compression) as archive:
        for name, content in files.items():
            data = content.encode("utf-8") if isinstance(content, str) else content
            archive.writestr(name, data)
    return buffer.getvalue()


def test_archive_scans_supported_files_and_ignores_dependencies() -> None:
    content = build_zip(
        {
            "src/app.py": 'api_key = "super-secret-value"\nprint("ready")',
            "src/view.ets": "const title: string = 'GuardianHub';",
            "node_modules/pkg/index.js": 'token = "dependency-secret-value";',
            "assets/logo.png": b"\x89PNG\r\n\x1a\n\x00\x00",
        }
    )

    result = analyze_code_archive(content, "guardianhub.zip", "local", DEFAULT_LIMITS)

    assert result["scanMode"] == "project"
    assert result["projectName"] == "guardianhub"
    assert result["scannedFiles"] == 2
    assert result["skippedFiles"] == 2
    assert result["languages"] == {"python": 1, "typescript": 1}
    assert result["riskLevel"] == "high"
    assert result["shouldSubmit"] is False
    assert result["vulnerabilities"][0]["filePath"] == "src/app.py"
    assert result["topRiskFiles"][0]["path"] == "src/app.py"


def test_archive_online_mode_does_not_send_the_whole_project() -> None:
    content = build_zip({"main.py": 'password = "super-secret-value"'})
    result = analyze_code_archive(content, "project.zip", "online", DEFAULT_LIMITS)
    assert result["detectorSource"] == "rule"
    assert "不会把整个压缩包发送" in result["deepseekWarning"]


def test_archive_rejects_zip_slip_path() -> None:
    content = build_zip({"../evil.py": "print('bad')"})
    with pytest.raises(ArchiveValidationError, match="不安全路径"):
        analyze_code_archive(content, "unsafe.zip", "local", DEFAULT_LIMITS)


def test_archive_rejects_too_many_files() -> None:
    content = build_zip({f"src/file_{index}.py": "print('ok')" for index in range(3)})
    limits = ArchiveLimits(
        max_entries=2,
        max_uncompressed_bytes=1024 * 1024,
        max_file_bytes=128 * 1024,
        max_compression_ratio=100,
    )
    with pytest.raises(ArchiveValidationError, match="条目过多"):
        analyze_code_archive(content, "large.zip", "local", limits)


def test_archive_counts_directory_entries_toward_limit() -> None:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("src/", "")
        archive.writestr("src/nested/", "")
        archive.writestr("src/main.py", "print('ok')")
    limits = ArchiveLimits(
        max_entries=2,
        max_uncompressed_bytes=1024 * 1024,
        max_file_bytes=128 * 1024,
        max_compression_ratio=100,
    )
    with pytest.raises(ArchiveValidationError, match="条目过多"):
        analyze_code_archive(buffer.getvalue(), "directories.zip", "local", limits)


def test_archive_rejects_total_uncompressed_size() -> None:
    content = build_zip({"src/large.py": "A" * 4096}, compression=zipfile.ZIP_STORED)
    limits = ArchiveLimits(
        max_entries=20,
        max_uncompressed_bytes=1024,
        max_file_bytes=8192,
        max_compression_ratio=100,
    )
    with pytest.raises(ArchiveValidationError, match="解压后总大小"):
        analyze_code_archive(content, "large.zip", "local", limits)


def test_archive_rejects_suspicious_compression_ratio() -> None:
    content = build_zip({"src/repeated.py": "A" * 10_000})
    limits = ArchiveLimits(
        max_entries=20,
        max_uncompressed_bytes=1024 * 1024,
        max_file_bytes=128 * 1024,
        max_compression_ratio=5,
    )
    with pytest.raises(ArchiveValidationError, match="解压炸弹"):
        analyze_code_archive(content, "bomb.zip", "local", limits)


def test_archive_rejects_symbolic_links() -> None:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        info = zipfile.ZipInfo("src/link.py")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, "target.py")
    with pytest.raises(ArchiveValidationError, match="符号链接"):
        analyze_code_archive(buffer.getvalue(), "links.zip", "local", DEFAULT_LIMITS)


def test_archive_rejects_non_regular_unix_entries() -> None:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        info = zipfile.ZipInfo("src/pipe.py")
        info.create_system = 3
        info.external_attr = (stat.S_IFIFO | 0o644) << 16
        archive.writestr(info, "print('unsafe')")
    with pytest.raises(ArchiveValidationError, match="非普通文件"):
        analyze_code_archive(buffer.getvalue(), "special.zip", "local", DEFAULT_LIMITS)


def test_archive_rejects_duplicate_normalized_paths() -> None:
    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("src/Main.py", "print('one')")
        archive.writestr("src/main.py", "print('two')")
    with pytest.raises(ArchiveValidationError, match="重复路径"):
        analyze_code_archive(buffer.getvalue(), "duplicates.zip", "local", DEFAULT_LIMITS)


def test_archive_rejects_corrupted_zip() -> None:
    with pytest.raises(ArchiveValidationError, match="无效或已经损坏"):
        analyze_code_archive(b"not a zip archive", "broken.zip", "local", DEFAULT_LIMITS)


def test_archive_requires_at_least_one_scannable_text_file() -> None:
    content = build_zip({"assets/logo.bin": b"\x00\x01\x02"})
    with pytest.raises(ArchiveValidationError, match="没有可扫描"):
        analyze_code_archive(content, "binary.zip", "local", DEFAULT_LIMITS)
