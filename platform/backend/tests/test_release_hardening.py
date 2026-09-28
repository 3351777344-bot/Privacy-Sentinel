import base64
import json
import subprocess
from datetime import datetime, timedelta, timezone
from dataclasses import replace

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from fastapi.testclient import TestClient

import config
import main
from modules.doc_shield.signed_feed import install, verify


@pytest.mark.parametrize('path,kwargs,forbidden_name', [
    ('/api/code/analyze', {'json': {'code': 'print(1)', 'processingMode': 'online'}}, 'run_code_guardian'),
    ('/api/detect', {'data': {'processing_mode': 'online'}, 'files': {'file': ('x.png', b'x', 'image/png')}}, 'detect_privacy_items'),
    # Doc Shield spends model quota only in online mode, so the consent gate has
    # to reject the request before the requirement parse is even reached.
    ('/api/doc/check', {
        'data': {'requirement_text': '请提交 PDF', 'processing_mode': 'online'},
        'files': {'files': ('报告.txt', '正文'.encode('utf-8'), 'text/plain')},
    }, '_run_online_doc_analysis'),
])
def test_online_analysis_requires_explicit_consent(path, kwargs, forbidden_name, monkeypatch):
    def forbidden(*args, **kw):
        pytest.fail('analysis ran without consent')
    monkeypatch.setattr(main, forbidden_name, forbidden)
    assert TestClient(main.app).post(path, **kwargs).status_code == 403


def test_health_reports_configured_build_version(monkeypatch):
    monkeypatch.setattr(main, "settings", replace(main.settings, build_version="abc123"))
    payload = TestClient(main.app).get("/api/health").json()
    assert payload["version"] == "abc123"
    assert set(("status", "version", "buildTime", "privacyDetector")) <= payload.keys()


def test_build_version_defaults_to_the_running_commit(monkeypatch):
    """The default must come from git, not from a hand-maintained variable.

    ``/api/health`` exists to answer "is this deployment current?". A manual value
    goes stale the first time someone pulls without editing it, and that actually
    happened: the deployed service reported the commit *before* the one it ran.
    """
    monkeypatch.delenv("GUARDIANHUB_BUILD_VERSION", raising=False)
    monkeypatch.setattr(config, "load_dotenv", lambda *a, **k: None)  # keep a real .env out of the way

    detected = config._detect_build_version()
    if detected == "unknown":
        pytest.skip("git or .git unavailable in this checkout")

    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                          cwd=config._repo_root(), capture_output=True, text=True).stdout.strip()
    assert head, "git 未能给出 HEAD"
    assert detected.startswith(head), f"检测结果 {detected!r} 与 HEAD {head!r} 不符"
    dirty = bool(subprocess.run(["git", "status", "--porcelain"],
                                cwd=config._repo_root(), capture_output=True, text=True).stdout.strip())
    assert detected.endswith("-dirty") is dirty


def test_build_version_override_wins(monkeypatch):
    """A checkout without .git still needs to be able to declare itself."""
    monkeypatch.setenv("GUARDIANHUB_BUILD_VERSION", "release-2026-09-28")
    assert config._detect_build_version() == "release-2026-09-28"


def test_build_version_never_raises_without_git(monkeypatch):
    """A version probe must not be able to stop the service from starting."""
    monkeypatch.delenv("GUARDIANHUB_BUILD_VERSION", raising=False)

    def explode(*args, **kwargs):
        raise FileNotFoundError("git missing")

    monkeypatch.setattr(config.subprocess, "run", explode)
    assert config._detect_build_version() == "unknown"


def envelope(key, version=1, days=1):
    now = datetime.now(timezone.utc)
    payload = {'version': version, 'updated_at': (now - timedelta(days=2)).isoformat(),
               'expires_at': (now + timedelta(days=days)).isoformat(), 'entries': []}
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    return json.dumps({'payload': payload, 'signature': base64.b64encode(key.sign(canonical)).decode()}).encode()


def test_signed_feed_transaction_and_replay(tmp_path):
    key = Ed25519PrivateKey.generate()
    public = key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    path = tmp_path / 'feed.json'
    first = envelope(key)
    install(path, first, public)
    with pytest.raises(ValueError):
        install(path, first, public)
    with pytest.raises(Exception):
        install(path, envelope(Ed25519PrivateKey.generate(), 2), public)
    assert path.read_bytes() == first
    with pytest.raises(ValueError):
        verify(envelope(key, 2, -1), public)
    install(path, envelope(key, 2), public)
    assert path.with_suffix('.previous.json').read_bytes() == first
