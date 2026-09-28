"""Non-secret-printing tracked configuration, artifact and documentation checks.

Two invariants are enforced here, both of which used to be asserted by prose
instead of by code:

* no signing secret is present in a tracked config file;
* every artifact claimed in the release manifest exists and really hashes to the
  recorded digest, and no extra binary is tracked under the release directory.

``*.hap`` is gitignored, so the manifest can never ship the binary itself.
Artifacts and the manifest live outside the repository (submission materials are
kept separate from project code). The delivery directory is resolved in this
order: ``GUARDIANHUB_DELIVERY_DIR`` if set, then ``GuardianHub-delivery`` next to
the repository, then ``<home>/GuardianHub-delivery``.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]


def _delivery_dir() -> Path:
    override = os.environ.get("GUARDIANHUB_DELIVERY_DIR")
    if override:
        return Path(override)
    sibling = root.parent / "GuardianHub-delivery"
    if sibling.is_dir():
        return sibling
    return Path.home() / "GuardianHub-delivery"


DELIVERY = _delivery_dir()
MANIFEST = Path("submission-materials/release/SHA256SUMS.txt")
# Documentation that legitimately lives beside the manifest and is not an artifact.
NON_ARTIFACTS = {"RELEASE_NOTES.md"}
# Artifacts are gitignored; this is where the build actually drops them.
HARMONY_OUTPUT = Path("platform/harmony/entry/build/default/outputs/default")
MANIFEST_ENTRY = re.compile(r"^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$")


def tracked_files() -> list[str]:
    return subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")


def resolve_artifact(name: str) -> Path | None:
    """Find an artifact by its recorded path, tolerating the build output dir."""
    relative = Path(name)
    candidates = [root / relative]
    if len(relative.parts) > 1:
        # A delivery-time copy path such as ``release/x.hap`` may instead be
        # relative to where the build drops it.
        candidates.append(root / HARMONY_OUTPUT / relative.name)
    candidates.append(DELIVERY / MANIFEST.parent / relative.name)
    candidates.append(DELIVERY / relative.name)
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def artifact_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def manifest_path() -> Path:
    """The manifest lives with the delivery materials, outside the repository."""
    return DELIVERY / MANIFEST


def read_manifest() -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    path = manifest_path()
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        match = MANIFEST_ENTRY.match(line)
        if match is None:
            raise ValueError(f"{path}:{number} 不是合法的 sha256sum 行：{line!r}")
        entries.append((match.group(1).upper(), match.group(2)))
    if not entries:
        raise ValueError(f"{path} 存在但没有内容；请用 tools/release-check.py --write 生成")
    return entries


def write_manifest(names: list[str]) -> int:
    lines = []
    for name in names:
        artifact = resolve_artifact(name)
        if artifact is None:
            print(f"无法生成清单：找不到产物 {name}", file=sys.stderr)
            return 1
        lines.append(f"{artifact_digest(artifact)}  {name}")
    path = manifest_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{path} 已写入 {len(lines)} 条（对应磁盘上的真实产物）。")
    return 0


def check_configuration(paths: list[str]) -> list[str]:
    failures: list[str] = []
    profile = json.loads((root / "platform/harmony/build-profile.json5").read_text(encoding="utf-8"))
    if profile["app"]["signingConfigs"] != []:
        failures.append("platform/harmony/build-profile.json5: tracked signing config must be empty")
    for name in paths:
        path = root / name
        if not name or not path.is_file() or path.suffix.lower() not in (".json5", ".json", ".yml", ".yaml", ".env"):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r'"(?:storePassword|keyPassword)"\s*:\s*"[^"\s]+"', text):
            failures.append(name + ": signing password present")
    return failures


def check_artifacts(paths: list[str]) -> tuple[list[str], list[str]]:
    """Return (failures, notes) for the release manifest and tracked binaries."""
    failures: list[str] = []
    notes: list[str] = []
    for name in paths:
        if Path(name).suffix.lower() in (".hap", ".hsp", ".har"):
            failures.append(f"{name}: build artifact must stay gitignored, not tracked")
    if not manifest_path().exists():
        notes.append(
            f"{manifest_path()} 不存在：尚未生成本次发布的产物清单"
            "（执行 tools/release-check.py --write 生成；交付材料与清单都在仓库之外）。"
        )
        return failures, notes

    try:
        entries = read_manifest()
    except ValueError as error:
        failures.append(str(error))
        return failures, notes

    for digest, name in entries:
        artifact = resolve_artifact(name)
        if artifact is None:
            failures.append(
                f"{manifest_path()}: 记录的产物 {name} 在本机找不到"
                f"（查找位置：仓库根、{HARMONY_OUTPUT}、{DELIVERY}）"
            )
            continue
        actual = artifact_digest(artifact)
        if actual != digest:
            failures.append(f"{manifest_path()}: {name} 实际 SHA-256 {actual} != 记录 {digest}")
        else:
            notes.append(f"{name} 校验通过：{artifact.stat().st_size} 字节，SHA-256 {actual}")
    return failures, notes


def check_readme_links() -> list[str]:
    failures: list[str] = []
    for name in ["README.md", "platform/README.md"]:
        path = root / name
        if not path.is_file():
            continue
        for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
            if "://" in target or target.startswith("#"):
                continue
            if not (path.parent / target.split("#")[0]).exists():
                failures.append(name + f": broken relative link -> {target}")
    return failures


def check_hap_contents() -> tuple[list[str], list[str]]:
    """Check local HAP contents when build output is available."""
    failures: list[str] = []
    notes: list[str] = []
    output_dir = root / HARMONY_OUTPUT
    app_scope = (root / "platform/harmony/AppScope/app.json5").read_text(encoding="utf-8")
    expected_bundle = re.search(r'"bundleName"\s*:\s*"([^"]+)"', app_scope)
    expected_version_code = re.search(r'"versionCode"\s*:\s*(\d+)', app_scope)
    expected_version_name = re.search(r'"versionName"\s*:\s*"([^"]+)"', app_scope)
    for hap in sorted(output_dir.glob("*.hap")) if output_dir.is_dir() else []:
        try:
            with zipfile.ZipFile(hap) as archive:
                payload = b"\n".join(archive.read(name) for name in archive.namelist())
                module_name = next((name for name in archive.namelist() if name.endswith("module.json")), None)
                module = json.loads(archive.read(module_name)) if module_name else {}
        except (OSError, zipfile.BadZipFile, json.JSONDecodeError) as error:
            failures.append(f"{hap}: 无法读取 HAP 内容（{error}）")
            continue
        if b"https://api.guardianhub.tech" not in payload:
            failures.append(f"{hap}: 未包含生产 HTTPS 地址 https://api.guardianhub.tech")
        for forbidden in (b"10.0.2.2:8001", b"127.0.0.1", b"localhost"):
            if forbidden in payload:
                failures.append(f"{hap}: 包含禁止的开发地址 {forbidden.decode()}")
        app = module.get("app", module)
        if expected_bundle and app.get("bundleName") and app["bundleName"] != expected_bundle.group(1):
            failures.append(f"{hap}: bundleName 与 AppScope 不一致")
        if expected_version_code and app.get("versionCode") not in (None, int(expected_version_code.group(1))):
            failures.append(f"{hap}: versionCode 与 AppScope 不一致")
        if expected_version_name and app.get("versionName") not in (None, expected_version_name.group(1)):
            failures.append(f"{hap}: versionName 与 AppScope 不一致")
        notes.append(
            f"{hap.name} 地址与包元数据检查通过：{hap.stat().st_size} 字节，"
            f"versionCode={app.get('versionCode', 'unknown')}，versionName={app.get('versionName', 'unknown')}"
        )
    return failures, notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        nargs="*",
        metavar="ARTIFACT",
        help="生成 SHA256SUMS.txt；不带参数时写入默认的调试 HAP 名称",
    )
    options = parser.parse_args()

    if options.write is not None:
        return write_manifest(options.write or ["GuardianHub-debug-unsigned.hap"])

    paths = tracked_files()
    failures = check_configuration(paths)
    artifact_failures, notes = check_artifacts(paths)
    failures += artifact_failures
    failures += check_readme_links()
    hap_failures, hap_notes = check_hap_contents()
    failures += hap_failures
    notes += hap_notes

    for note in notes:
        print("note: " + note)
    if failures:
        print("\n".join("FAIL: " + item for item in failures), file=sys.stderr)
        return 1
    print("Release checks passed; Harmony HAP and real-device regression remain separate gates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
