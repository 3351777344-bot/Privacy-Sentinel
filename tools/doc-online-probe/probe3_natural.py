"""Ask whether the online pass really reads free-form prose.

The earlier probe fed a requirement that still contained the rule vocabulary
("提交…PDF…文件名使用…截止时间"). This one is deliberately conversational and
carries none of it, so a passing result can only come from the model.

Run:  python tools/doc-online-probe/probe3_natural.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = os.environ.get("GUARDIANHUB_API_BASE", "https://api.guardianhub.tech").rstrip("/")
PAPER = HERE / "course-paper-natural.txt"

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# Conversational, no format words, no "截止时间", no "材料清单". The kind of thing
# a classmate would actually paste into a group chat.
NATURAL = (
    "老师昨天在群里说的，让我们下周之前把东西发他邮箱，"
    "说别拿网上抄的糊弄他，要看我们自己写的，最好把过程和结果都讲清楚。"
)

STRUCTURED = (
    "提交课程论文 PDF、封面和签字承诺书；文件名使用学号_姓名_课程名称；"
    "截止时间 2026 年 7 月 26 日 20:00。"
)


def post(requirement: str, mode: str, consent: bool, timeout: int = 300):
    boundary = f"----gh{uuid.uuid4().hex}"
    paper = PAPER.read_bytes()
    parts: list[bytes] = []

    def field(name: str, value: str) -> None:
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n'
            f"Content-Type: text/plain\r\n\r\n".encode() + value.encode() + b"\r\n"
        )

    field("requirement_text", requirement)
    field("processing_mode", mode)
    parts.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="files"; '
        f'filename="{PAPER.name}"\r\nContent-Type: text/plain\r\n\r\n'.encode()
        + paper + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())

    request = urllib.request.Request(f"{BASE}/api/doc/check", data=b"".join(parts), method="POST")
    request.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    if consent:
        request.add_header("X-Guardian-Consent", "explicit")
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, json.loads(response.read().decode("utf-8")), time.monotonic() - started
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", "replace")
        try:
            return error.code, json.loads(raw), time.monotonic() - started
        except json.JSONDecodeError:
            return error.code, {"raw": raw[:300]}, time.monotonic() - started
    except Exception as error:  # noqa: BLE001
        return -1, {"error": f"{type(error).__name__}: {error}"}, time.monotonic() - started


def report(title: str, status: int, payload: dict, elapsed: float) -> None:
    print(f"\n=== {title} (HTTP {status}, {elapsed:.1f}s) ===")
    if "detail" in payload:
        print("detail:", payload["detail"])
        return
    if "error" in payload:
        print("error:", payload["error"])
        return
    parsed = payload.get("parsedRequirements", {})
    for key in ("source", "sourceFields", "contentRequirements", "modelWarning",
                "formats", "namingRule", "requiredMaterials", "lengthRequirement", "deadline"):
        print(f"  {key:<20}: {parsed.get(key)}")
    print(f"  checks              : {len(payload.get('checks', []))}")
    for check in payload.get("checks", []):
        print(f"    - [{check['category']}] {check['label']} | {check['status']}")
    print(f"  summary             : {payload.get('summary')}")


def main() -> int:
    if not PAPER.is_file():
        print("缺少语料:", PAPER)
        return 2
    print("口语化要求：", NATURAL)
    status, payload, elapsed = post(NATURAL, "local", False)
    report("口语化 · local（规则表能读出什么）", status, payload, elapsed)
    status, payload, elapsed = post(NATURAL, "online", True)
    report("口语化 · online（模型能读出什么）", status, payload, elapsed)
    status, payload, elapsed = post(STRUCTURED, "online", True)
    report("对照 · 规则化措辞 online", status, payload, elapsed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
