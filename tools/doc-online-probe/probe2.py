"""Second probe: the vague-requirement fallback path and the rate-limit budget.

Uses urllib instead of curl so the multipart body is built by the standard
library (the earlier "000" was a client-side connection failure, not a server
verdict). Prints only the fields that decide the two questions:

1. Does a requirement the model cannot use fall back field-by-field, keep
   source=local, and explain itself via modelWarning?
2. Is /api/doc/check counted against the model budget, and does a legitimate
   burst stay under it?
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
# Same default as probe.py; GUARDIANHUB_API_BASE points either probe at a local
# or staging deployment instead of production.
BASE = os.environ.get("GUARDIANHUB_API_BASE", "https://api.guardianhub.tech").rstrip("/")
PAPER = (HERE / "course-paper.txt") if (HERE / "course-paper.txt").is_file() \
    else Path(__file__).resolve().parents[2] / "platform/samples/doc-risky/course-paper.txt"
DIR = HERE

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def post(requirement: str, mode: str, consent: bool = False, timeout: int = 300):
    boundary = f"----guardianhub{uuid.uuid4().hex}"
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
        f'filename="course-paper.txt"\r\nContent-Type: text/plain\r\n\r\n'.encode()
        + paper + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)

    request = urllib.request.Request(f"{BASE}/api/doc/check", data=body, method="POST")
    request.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    if consent:
        request.add_header("X-Guardian-Consent", "explicit")
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
            headers = dict(response.headers)
            return response.status, payload, time.monotonic() - started, headers
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", "replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw[:300]}
        return error.code, payload, time.monotonic() - started, dict(error.headers)
    except Exception as error:  # noqa: BLE001 - probe reports, never raises
        return -1, {"error": f"{type(error).__name__}: {error}"}, time.monotonic() - started, {}


def main() -> int:
    vague = (DIR / "requirement-vague.txt").read_text(encoding="utf-8")
    content = (DIR / "requirement-content.txt").read_text(encoding="utf-8")

    print("=== ③ 模糊要求 online（逐字段回退）===")
    for attempt in range(1, 4):
        status, payload, elapsed, _ = post(vague, "online", consent=True)
        print(f"  第 {attempt} 次: HTTP {status}, {elapsed:.1f}s")
        if status == 200:
            parsed = payload["parsedRequirements"]
            print("  source            :", parsed.get("source"))
            print("  sourceFields      :", parsed.get("sourceFields"))
            print("  modelWarning      :", parsed.get("modelWarning"))
            print("  contentRequirements:", parsed.get("contentRequirements"))
            print("  formats/naming    :", parsed.get("formats"), "/", parsed.get("namingRule"))
            print("  checks            :", len(payload.get("checks", [])))
            print("  summary           :", payload.get("summary"))
            break
        if isinstance(payload, dict) and payload.get("detail"):
            print("  detail:", payload["detail"])
        time.sleep(3)

    print("\n=== ⑥ 限流：连打 6 次 online，看是否出现 429 与余量提示 ===")
    for index in range(1, 7):
        status, payload, elapsed, headers = post(content, "online", consent=True)
        hint = {k: v for k, v in headers.items() if "ratelimit" in k.lower() or k.lower() == "retry-after"}
        detail = payload.get("detail") if isinstance(payload, dict) else payload
        print(f"  #{index}: HTTP {status}, {elapsed:.1f}s, 限流头={hint or '无'}"
              + (f", detail={detail}" if status >= 400 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
