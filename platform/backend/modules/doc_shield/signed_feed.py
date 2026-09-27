"""Offline Ed25519 feed verification and transactional installation.

The operator pins a public key; no network download or private key is needed.
The signature covers canonical JSON (UTF-8, sorted keys, compact separators).
"""
import base64
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

MAX_BYTES = 2 * 1024 * 1024


def verify(raw: bytes, public_key: bytes, minimum_version: int = 0) -> dict:
    """Verify signature, validity window and entries.

    ``minimum_version`` is the oldest version still accepted, so re-verifying
    the currently installed feed is allowed while a replayed older one is not.
    """
    if len(raw) > MAX_BYTES:
        raise ValueError('feed too large')
    envelope = json.loads(raw)
    payload = envelope['payload']
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    Ed25519PublicKey.from_public_bytes(public_key).verify(
        base64.b64decode(envelope['signature'], validate=True), canonical)
    version = payload['version']
    if type(version) is not int or version < minimum_version:
        raise ValueError('feed version must not decrease')
    now = datetime.now(timezone.utc)
    updated = datetime.fromisoformat(payload['updated_at'])
    expires = datetime.fromisoformat(payload['expires_at'])
    if updated.tzinfo is None or expires.tzinfo is None or updated > now or expires <= now or expires <= updated:
        raise ValueError('invalid feed validity period')
    entries = payload['entries']
    if not isinstance(entries, list) or len(entries) > 10000:
        raise ValueError('invalid feed entries')
    seen = set()
    for entry in entries:
        digest = entry['indicator']
        if entry['indicator_type'] != 'sha256' or not re.fullmatch('[a-f0-9]{64}', digest) or digest in seen:
            raise ValueError('invalid or duplicate hash')
        seen.add(digest)
        if entry['verdict'] not in ('malicious', 'suspicious') or not 0 <= entry['confidence'] <= 1:
            raise ValueError('invalid verdict')
        if not isinstance(entry['source'], str) or not entry['source'].strip():
            raise ValueError('source required')
    return payload


def _atomic_write(path: Path, raw: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.feed-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def install(path: Path, raw: bytes, public_key: bytes, minimum_version: int = 0) -> dict:
    """Verify before replacing; retain previous bytes for operator recovery.

    The replacement must be signed and strictly newer than both
    ``minimum_version`` and the feed currently on disk, so a replayed older
    envelope cannot roll the library back.
    """
    current = path.read_bytes() if path.exists() else None
    version = minimum_version
    if current is not None:
        if len(current) > MAX_BYTES:
            raise ValueError('installed feed too large')
        # Authenticate old version even if its validity period has expired.
        old = json.loads(current)
        canonical = json.dumps(old['payload'], ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
        Ed25519PublicKey.from_public_bytes(public_key).verify(base64.b64decode(old['signature'], validate=True), canonical)
        version = max(version, old['payload']['version'])
    payload = verify(raw, public_key, version + 1)
    if current is not None:
        _atomic_write(path.with_suffix('.previous.json'), current)
    _atomic_write(path, raw)
    return payload
