"""Does a conversational deadline now reach the report as a real date?

The only piece that needs the live deployment: the model quotes "下周之前" and
the server-side resolver turns it into a date on China time. Everything after
that (parsing, comparison against now) is pure backend code.

Run:  python tools/doc-online-probe/probe4_deadline.py
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
BRIEF = "老师昨天在群里说的，让我们下周之前把东西发他邮箱，说别拿网上抄的糊弄他，要看我们自己写的，最好把过程和结果都讲清楚。"

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


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


def main() -> int:
    print("要求原文：", BRIEF)
    status, payload, elapsed = post(BRIEF, "online", consent=True)
    print(f"\nHTTP {status}, {elapsed:.1f}s")
    if status != 200:
        print(json.dumps(payload, ensure_ascii=False, indent=2)[:600])
        return 1 if status != 200 else 0

    parsed = payload["parsedRequirements"]
    print("deadline           :", parsed.get("deadline"))
    print("sourceFields       :", parsed.get("sourceFields"))
    print("contentRequirements:", parsed.get("contentRequirements"))
    print("notes              :", parsed.get("notes"))
    print("截止/期限相关检查行：")
    for check in payload.get("checks", []):
        if "截止" in check["label"] or "期限" in check["label"]:
            print(f"  - {check['label']} | {check['status']} | {check['evidence']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
