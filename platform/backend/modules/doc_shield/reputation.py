"""L3 — cloud-assisted reputation lookup.

The on-device scanners are the primary defence; this service is a second
opinion for files whose structure is suspicious but not conclusive. The privacy
boundary is strict and enforced here, not just by convention:

* the device submits a SHA-256 digest, never file content;
* nothing in a request is persisted — no query log, no digest cache.

Production entries come only from ``data/threat_feed.signed.json`` verified
against an operator-pinned Ed25519 key. Unsigned legacy CSV/IoC files are
ignored, and SHA-256 is the only supported indicator type: a signature is what
makes the blocklist trustworthy, so the lookup surface stays on hashes instead
of advertising a domain/IoC match that would silently return nothing.

Unknown hashes are reported as unknown; the built-in EICAR vector is test-only.
"""

from __future__ import annotations

import base64
import logging
import os
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional

from .signed_feed import verify

logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = BASE_DIR / "data"
FEED_FILE = DATA_DIR / "threat_feed.signed.json"
PUBLIC_KEY_ENV = "GUARDIANHUB_FEED_PUBLIC_KEY"

_SEED_HASHES: Dict[str, Dict[str, str]] = {
    # Public, harmless antivirus test vector — proves the lookup path end to end.
    "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f": {
        "family": "EICAR 测试文件",
        "firstSeen": "1991-01-01",
        "source": "builtin",
        "note": "行业标准反病毒测试样本，本身无害。",
    }
}


def _normalise_hash(value: str) -> str:
    if not isinstance(value, str):
        return ""
    candidate = value.strip().lower()
    if len(candidate) != 64:
        return ""
    if any(ch not in "0123456789abcdef" for ch in candidate):
        return ""
    return candidate


class ThreatFeed:
    """Lazily-loaded, thread-safe reputation feed.

    The feed file is re-read when its modification time changes, so an operator
    can drop in a new feed without restarting the service. Expiry is re-checked
    on every access, including after the file disappears: a revoked or expired
    feed degrades to the built-in seed instead of serving stale verdicts.
    """

    def __init__(self) -> None:
        self._hashes: Dict[str, Dict[str, str]] = dict(_SEED_HASHES)
        self._version: str = "builtin"
        self._entries: int = len(self._hashes)
        self._stamp: Optional[int] = None
        self._min_version: int = 0
        self._expires_at: Optional[datetime] = None
        self._load_error: Optional[str] = None
        self._status: str = "unconfigured"
        self._lock = threading.RLock()

    # ------------------------------------------------------------- loading
    def _stat_signature(self) -> Optional[int]:
        try:
            return FEED_FILE.stat().st_mtime_ns
        except OSError:
            return None

    @staticmethod
    def _public_key() -> Optional[bytes]:
        key_text = os.environ.get(PUBLIC_KEY_ENV, "").strip()
        if not key_text:
            return None
        try:
            key = base64.b64decode(key_text, validate=True)
        except Exception as error:  # binascii.Error and friends
            raise ValueError(f"{PUBLIC_KEY_ENV} 不是合法的 Base64 公钥") from error
        if len(key) != 32:
            raise ValueError(f"{PUBLIC_KEY_ENV} 必须是 32 字节 Ed25519 公钥")
        return key

    def _fail(self, reason: str, error: BaseException) -> None:
        """Keep the last valid in-memory feed, but make the failure visible."""
        self._load_error = reason
        if self._expires_at and self._expires_at > datetime.now(timezone.utc):
            logger.warning("威胁情报更新失败（%s），继续使用上一份未过期情报：%r", reason, error)
            self._status = "stale"
            return
        logger.warning("威胁情报不可用（%s），本次回退到内置种子：%r", reason, error)
        self._hashes = dict(_SEED_HASHES)
        self._entries = len(self._hashes)
        self._version = "builtin"
        self._expires_at = None
        self._status = "unavailable"

    def _reload(self, public_key: Optional[bytes]) -> None:
        if public_key is None:
            return
        if not FEED_FILE.exists():
            # The feed was removed: drop signed entries, fall back to the seed.
            self._hashes = dict(_SEED_HASHES)
            self._entries = len(self._hashes)
            self._version = "builtin"
            self._expires_at = None
            self._load_error = None
            self._status = "unconfigured"
            return
        try:
            # Verify only: the file on disk is the operator's copy, and passing
            # the highest version ever loaded means a replayed older envelope
            # cannot roll the in-memory library back.
            payload = verify(FEED_FILE.read_bytes(), public_key, self._min_version)
        except Exception as error:
            self._fail("签名或格式校验失败", error)
            return

        hashes: Dict[str, Dict[str, str]] = dict(_SEED_HASHES)
        for entry in payload["entries"]:
            hashes[entry["indicator"]] = {
                "family": entry.get("family", entry["verdict"]),
                "firstSeen": entry.get("first_seen", ""),
                "source": entry["source"],
                "confidence": str(round(entry["confidence"] * 100)),
            }
        self._hashes = hashes
        self._entries = len(hashes)
        self._version = f'signed:{payload["version"]}'
        self._min_version = payload["version"]
        self._expires_at = datetime.fromisoformat(payload["expires_at"])
        self._load_error = None
        self._status = "signed"

    def _ensure_loaded(self) -> None:
        stamp = self._stat_signature()
        with self._lock:
            if stamp is not None and stamp == self._stamp:
                expires = self._expires_at
                if expires is None or expires > datetime.now(timezone.utc):
                    return
            # No feed file, a changed file, or expired in-memory data: reload.
            try:
                public_key = self._public_key()
            except ValueError as error:
                self._fail(f"{PUBLIC_KEY_ENV} 配置非法", error)
                self._stamp = stamp
                return
            self._reload(public_key)
            self._stamp = stamp

    # ------------------------------------------------------------ querying
    @property
    def version(self) -> str:
        self._ensure_loaded()
        return self._version

    @property
    def entries(self) -> int:
        self._ensure_loaded()
        return self._entries

    @property
    def status(self) -> str:
        """``unconfigured`` | ``signed`` | ``stale`` | ``unavailable``."""
        self._ensure_loaded()
        return self._status

    @property
    def last_error(self) -> Optional[str]:
        self._ensure_loaded()
        return self._load_error

    def lookup_hash(self, sha256: str) -> Optional[Dict[str, str]]:
        digest = _normalise_hash(sha256)
        if not digest:
            return None
        self._ensure_loaded()
        with self._lock:
            entry = self._hashes.get(digest)
        return dict(entry) if entry else None

    def has_feed(self) -> bool:
        self._ensure_loaded()
        return self._version != "builtin" or self._entries > len(_SEED_HASHES)


feed = ThreatFeed()
