import base64
import json
from datetime import datetime, timedelta, timezone

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from fastapi.testclient import TestClient

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
