"""L3 — cloud-assisted reputation lookup.

The on-device scanners are the primary defence; this service is a second
opinion for files whose structure is suspicious but not conclusive. The privacy
boundary is strict and enforced here, not just by convention:

* the device submits a SHA-256 digest plus indicators it already extracted,
  never file content;
* nothing in a request is persisted — no query log, no digest cache.

The feed itself is operator-supplied. Point ``data/threat_feed.csv`` at a
signed feed (``sha256,family,firstSeen,source``) and ``data/threat_iocs.txt`` at
a newline-separated list of known-bad domains/addresses/URLs. When neither
exists the service answers honestly — everything is reported as unknown rather
than inventing a verdict.
"""

from __future__ import annotations

import threading
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set

BASE_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = BASE_DIR / "data"
FEED_FILE = DATA_DIR / "threat_feed.csv"
IOC_FILE = DATA_DIR / "threat_iocs.txt"

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


def _normalise_indicator(value: str) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip().strip(".,;\"'").lower()


class ThreatFeed:
    """Lazily-loaded, thread-safe reputation feed.

    The files are re-read when their modification time changes, so an operator
    can drop in a new feed without restarting the service.
    """

    def __init__(self) -> None:
        self._hashes: Dict[str, Dict[str, str]] = dict(_SEED_HASHES)
        self._iocs: Set[str] = set()
        self._version: str = "builtin"
        self._entries: int = len(self._hashes)
        self._stamp: Optional[float] = None
        self._lock = threading.Lock()

    # ------------------------------------------------------------- loading
    def _stat_signature(self) -> Optional[float]:
        stamps: List[float] = []
        for path in (FEED_FILE, IOC_FILE):
            try:
                stamps.append(path.stat().st_mtime)
            except OSError:
                continue
        if not stamps:
            return None
        return max(stamps)

    def _reload(self) -> None:
        hashes: Dict[str, Dict[str, str]] = dict(_SEED_HASHES)
        iocs: Set[str] = set()
        version = "builtin"

        try:
            with FEED_FILE.open("r", encoding="utf-8") as handle:
                for raw_line in handle:
                    line = raw_line.strip()
                    if not line or line.startswith("#"):
                        continue
                    fields = [part.strip() for part in line.split(",")]
                    digest = _normalise_hash(fields[0])
                    if not digest:
                        continue
                    hashes[digest] = {
                        "family": fields[1] if len(fields) > 1 and fields[1] else "已知恶意样本",
                        "firstSeen": fields[2] if len(fields) > 2 else "",
                        "source": fields[3] if len(fields) > 3 and fields[3] else "feed",
                    }
            version = f"feed:{FEED_FILE.name}"
        except OSError:
            pass

        try:
            with IOC_FILE.open("r", encoding="utf-8") as handle:
                for raw_line in handle:
                    indicator = _normalise_indicator(raw_line)
                    if not indicator or indicator.startswith("#"):
                        continue
                    iocs.add(indicator)
            if version == "builtin":
                version = f"feed:{IOC_FILE.name}"
        except OSError:
            pass

        self._hashes = hashes
        self._iocs = iocs
        self._entries = len(hashes) + len(iocs)
        self._version = version

    def _ensure_loaded(self) -> None:
        stamp = self._stat_signature()
        with self._lock:
            if stamp is None and self._stamp is None:
                return
            if stamp != self._stamp:
                self._reload()
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

    def lookup_hash(self, sha256: str) -> Optional[Dict[str, str]]:
        digest = _normalise_hash(sha256)
        if not digest:
            return None
        self._ensure_loaded()
        with self._lock:
            entry = self._hashes.get(digest)
        return dict(entry) if entry else None

    def match_indicators(self, indicators: Sequence[str]) -> List[str]:
        """Return which of the supplied indicators appear in the blocklist."""
        if not indicators:
            return []
        self._ensure_loaded()
        matched: List[str] = []
        with self._lock:
            known = self._iocs
            if not known:
                return []
            for raw in indicators:
                candidate = _normalise_indicator(raw)
                if not candidate:
                    continue
                if candidate in known or any(
                    candidate.endswith("." + bad) or candidate.endswith("@" + bad)
                    for bad in known
                ):
                    matched.append(candidate)
        return matched

    def has_feed(self) -> bool:
        self._ensure_loaded()
        return self._version != "builtin" or self._entries > len(_SEED_HASHES)


feed = ThreatFeed()
