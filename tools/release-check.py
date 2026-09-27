"""Non-secret-printing tracked configuration, artifact and documentation checks.

Two invariants are enforced here, both of which used to be asserted by prose
instead of by code:

* no signing secret is present in a tracked config file;
* every artifact claimed in ``submission/release/SHA256SUMS.txt`` exists and
  really hashes to the recorded digest — and, conversely, no tracked file in
  that directory is left out of the manifest.

``*.hap`` is gitignored, so the manifest can never ship the binary itself. A
recorded path is resolved against the repository root, the documented Harmony
build output directory, and ``submission/release`` — the same places
``--write`` reads from.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
MANIFEST = Path("submission/release/SHA256SUMS.txt")
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
        # A submission-time copy path such as ``release/x.hap`` may instead be
        # relative to where the build drops it.
        candidates.append(root / HARMONY_OUTPUT / relative.name)
    candidates.append(root / "submission" / "release" / relative.name)
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


def read_manifest() -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for number, line in enumerate(MANIFEST.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        match = MANIFEST_ENTRY.match(line)
        if match is None:
            raise ValueError(f"{MANIFEST}:{number} 不是合法的 sha256sum 行：{line!r}")
        entries.append((match.group(1).upper(), match.group(2)))
    if not entries:
        raise ValueError(f"{MANIFEST} 存在但没有内容；请用 tools/release-check.py --write 生成")
    return entries


def write_manifest(names: list[str]) -> int:
    lines = []
    for name in names:
        artifact = resolve_artifact(name)
        if artifact is None:
            print(f"无法生成清单：找不到产物 {name}", file=sys.stderr)
            return 1
        lines.append(f"{artifact_digest(artifact)}  {name}")
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    (root / MANIFEST).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{MANIFEST} 已写入 {len(lines)} 条（对应磁盘上的真实产物）。")
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
    if not (root / MANIFEST).exists():
        notes.append(
            f"{MANIFEST} 不存在：尚未生成本次发布的产物清单"
            "（执行 tools/release-check.py --write 生成；CI 校验它一旦存在的内容）。"
        )
        return failures, notes

    try:
        entries = read_manifest()
    except ValueError as error:
        failures.append(str(error))
        return failures, notes

    recorded = {name for _, name in entries}
    for digest, name in entries:
        artifact = resolve_artifact(name)
        if artifact is None:
            failures.append(
                f"{MANIFEST}: 记录的产物 {name} 在本机找不到"
                f"（查找位置：仓库根、{HARMONY_OUTPUT}、submission/release）"
            )
            continue
        actual = artifact_digest(artifact)
        if actual != digest:
            failures.append(f"{MANIFEST}: {name} 实际 SHA-256 {actual} != 记录 {digest}")
        else:
            notes.append(f"{name} 校验通过：{artifact.stat().st_size} 字节，SHA-256 {actual}")

    manifest_name = MANIFEST.as_posix()
    for name in paths:
        parent = Path(name).parent.as_posix()
        if parent != "submission/release" or name == manifest_name:
            continue
        if Path(name).name in NON_ARTIFACTS or Path(name).name in recorded:
            continue
        failures.append(f"{MANIFEST}: 已跟踪的 {name} 既不是清单条目也不是说明文档")
    return failures, notes


def check_readme_links() -> list[str]:
    failures: list[str] = []
    for name in ["README.md", "submission/README.md"]:
        path = root / name
        for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
            if "://" in target or target.startswith("#"):
                continue
            if not (path.parent / target.split("#")[0]).exists():
                failures.append(name + f": broken relative link -> {target}")
    return failures


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

    for note in notes:
        print("note: " + note)
    if failures:
        print("\n".join("FAIL: " + item for item in failures), file=sys.stderr)
        return 1
    print("Release checks passed; Harmony HAP and real-device regression remain separate gates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
