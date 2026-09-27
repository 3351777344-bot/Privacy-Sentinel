"""Ad-hoc verification of the online Doc Shield requirement parsing (production).

Reads the fixtures beside this script (or a documents directory passed as the
first argument) and prints the fields the online pass is supposed to add, so the
result can be judged without decoding anything by eye.

It probes a live deployment on purpose: the unit tests inject fixed model
answers, so they cannot tell whether the real prompt still matches what the real
provider returns. See README.md for the recorded results and the open questions.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
# GUARDIANHUB_API_BASE points the probe at a local or staging deployment.
BASE = os.environ.get("GUARDIANHUB_API_BASE", "https://api.guardianhub.tech").rstrip("/")
DOCS = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE
DIR = DOCS if (DOCS / "requirement-content.txt").is_file() else HERE
PAPER = (HERE / "course-paper.txt") if (HERE / "course-paper.txt").is_file() \
    else Path(__file__).resolve().parents[2] / "platform/samples/doc-risky/course-paper.txt"
TIMEOUT = 300

try:  # keep Chinese readable regardless of the console codepage
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def call(requirement_file: str, mode: str, consent: bool = False) -> tuple[int, dict | str, float]:
    requirement = (DIR / requirement_file).read_text(encoding="utf-8")
    command = [
        "curl.exe", "-sS", "-m", str(TIMEOUT), "-w", "\n%{http_code}",
        "-X", "POST", f"{BASE}/api/doc/check",
        "--form-string", f"requirement_text={requirement}",
        "--form-string", f"processing_mode={mode}",
        "-F", f"files=@{PAPER};type=text/plain",
    ]
    if consent:
        command += ["-H", "X-Guardian-Consent: explicit"]
    started = time.monotonic()
    result = subprocess.run(
        command, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    elapsed = time.monotonic() - started
    body, _, status = result.stdout.rpartition("\n")
    try:
        return int(status), json.loads(body), elapsed
    except (ValueError, json.JSONDecodeError):
        return -1, (result.stdout or result.stderr or "<无输出>"), elapsed


def show(title: str, status: int, payload: dict | str, elapsed: float) -> None:
    print(f"\n=== {title} (HTTP {status}, {elapsed:.1f}s) ===")
    if not isinstance(payload, dict):
        print(payload)
        return
    if "detail" in payload:
        print("detail:", payload["detail"])
        return
    parsed = payload.get("parsedRequirements", {})
    for key in ("source", "sourceFields", "contentRequirements", "modelWarning",
                "lengthRequirement", "formats", "namingRule", "requiredMaterials",
                "deadline"):
        value = parsed.get(key, "<字段不存在>")
        print(f"  {key:<20}: {value}")
    print(f"  score/riskLevel     : {payload.get('score')} / {payload.get('riskLevel')}")
    print(f"  checks              : {len(payload.get('checks', []))}")
    for check in payload.get("checks", []):
        if str(check.get("label", "")).startswith(("内容", "在线")):
            print(f"    - [{check['category']}] {check['label']} | {check['status']} | {check['evidence']}")
    print(f"  suggestions[0]      : {(payload.get('suggestions') or ['<空>'])[0]}")
    print(f"  summary             : {payload.get('summary')}")


def main() -> int:
    print("fixtures:", [p.name for p in sorted(DIR.iterdir())])
    cases = [
        ("① 基线 local（对照组）", "requirement-content.txt", "local", False),
        ("② 联网解析 online（权限头已带）", "requirement-content.txt", "online", True),
        ("③ 模糊要求 online（应逐字段回退）", "requirement-vague.txt", "online", True),
        ("④ online 但缺授权头（应 403 且不调模型）", "requirement-content.txt", "online", False),
        ("⑤ 结果稳定性复跑", "requirement-content.txt", "online", True),
    ]
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    for title, requirement, mode, consent in cases:
        if only and only not in title:
            continue
        status, payload, elapsed = call(requirement, mode, consent)
        show(title, status, payload, elapsed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
