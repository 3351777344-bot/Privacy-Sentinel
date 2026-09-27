"""Regression tests for the signed reputation feed (L3 lookup).

Covers three failure modes that previously went unnoticed:
1. a replayed older feed rolling the library back;
2. expired in-memory entries still being served after the feed file is removed;
3. a misconfigured public key looking exactly like "not configured".
"""
import base64
import json
import logging
from datetime import datetime, timedelta, timezone

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from fastapi.testclient import TestClient

import main
from modules.doc_shield import reputation
from modules.doc_shield.signed_feed import install

DIGEST_V1 = "a" * 64
DIGEST_V2 = "b" * 64


def envelope(key, version, entries, days=1, updated_days_ago=2):
    now = datetime.now(timezone.utc)
    payload = {
        "version": version,
        "updated_at": (now - timedelta(days=updated_days_ago)).isoformat(),
        "expires_at": (now + timedelta(days=days)).isoformat(),
        "entries": [
            {
                "indicator": digest,
                "indicator_type": "sha256",
                "verdict": "malicious",
                "confidence": 0.9,
                "source": "unit-test",
            }
            for digest in entries
        ],
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return json.dumps(
        {"payload": payload, "signature": base64.b64encode(key.sign(canonical)).decode()}
    ).encode()


@pytest.fixture()
def feed_env(tmp_path, monkeypatch):
    """Isolate the reputation feed on a temp file and a freshly generated key."""
    key = Ed25519PrivateKey.generate()
    public = key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    path = tmp_path / "threat_feed.signed.json"
    monkeypatch.setattr(reputation, "FEED_FILE", path)
    monkeypatch.setenv(reputation.PUBLIC_KEY_ENV, base64.b64encode(public).decode())
    monkeypatch.setattr(reputation, "feed", reputation.ThreatFeed())
    monkeypatch.setattr(main, "threat_feed", reputation.feed)
    return key, path


def test_signed_feed_is_loaded_and_hash_matches(feed_env):
    key, path = feed_env
    install(path, envelope(key, 1, [DIGEST_V1]), key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw))
    assert reputation.feed.status == "signed"
    assert reputation.feed.version == "signed:1"
    assert reputation.feed.lookup_hash(DIGEST_V1) is not None
    assert reputation.feed.lookup_hash(DIGEST_V2) is None


def test_replayed_older_feed_cannot_roll_back(feed_env, caplog):
    """Replacing v2 with a validly signed v1 must be rejected, not applied."""
    key, path = feed_env
    public = key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    install(path, envelope(key, 2, [DIGEST_V2]), public)
    assert reputation.feed.lookup_hash(DIGEST_V2) is not None

    path.write_bytes(envelope(key, 1, [DIGEST_V1]))
    with caplog.at_level(logging.WARNING, logger=reputation.__name__):
        assert reputation.feed.lookup_hash(DIGEST_V1) is None
    assert "signed:2" in reputation.feed.version
    assert reputation.feed.last_error == "签名或格式校验失败"
    assert caplog.records, "a rejected feed must be logged, not swallowed silently"


def test_expired_feed_stops_serving_after_file_removal(feed_env):
    """An expired feed deleted by the operator must degrade to the built-in seed."""
    key, path = feed_env
    public = key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    path.write_bytes(envelope(key, 1, [DIGEST_V1], days=-1, updated_days_ago=3))

    entry = reputation.feed.lookup_hash(DIGEST_V1)
    assert entry is None, "expired signed entries must not be served as valid intel"
    assert reputation.feed.version == "builtin"
    assert reputation.feed.status == "unavailable"

    path.unlink()
    assert reputation.feed.status == "unconfigured"
    assert reputation.feed.lookup_hash(DIGEST_V1) is None


def test_invalid_public_key_is_distinguishable_from_missing(feed_env, caplog, monkeypatch):
    key, path = feed_env
    install(path, envelope(key, 1, [DIGEST_V1]), key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw))
    assert reputation.feed.status == "signed"
    # Force a reload so the freshly (mis)configured key has to be parsed again.
    monkeypatch.setattr(
        reputation.feed, "_expires_at", datetime.now(timezone.utc) - timedelta(seconds=1)
    )
    monkeypatch.setenv(reputation.PUBLIC_KEY_ENV, "not-base64!!")
    with caplog.at_level(logging.WARNING, logger=reputation.__name__):
        assert reputation.feed.lookup_hash(DIGEST_V1) is None
    assert reputation.feed.status == "unavailable"
    assert "配置非法" in (reputation.feed.last_error or "")
    assert caplog.records


def test_reputation_api_reports_feed_status_without_fabricating_matches(feed_env):
    """The endpoint must not report indicator-based hits and must expose feed health."""
    key, path = feed_env
    install(path, envelope(key, 3, [DIGEST_V1]), key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw))
    response = TestClient(main.app).post(
        "/api/doc/reputation",
        json={
            "files": [
                {
                    "sha256": DIGEST_V1,
                    "localVerdict": "clean",
                    "indicators": ["evil.example.com"],
                },
                {"sha256": DIGEST_V2, "localVerdict": "suspicious"},
            ]
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["feedVersion"] == "signed:3"
    assert body["feedStatus"] == "signed"
    known, unknown = body["results"]
    assert known["known"] is True and known["confidence"] == 90
    assert unknown["known"] is False
    assert all("域名" not in note for result in body["results"] for note in result["notes"]), (
        "the removed domain/IoC match must not resurface in notes"
    )
