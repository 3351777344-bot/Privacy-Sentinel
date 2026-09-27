import asyncio

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import main
from rate_limit import (
    RATE_LIMITED_DETAIL,
    RateLimitMiddleware,
    RateLimiter,
    SlidingWindow,
    budget_name,
    client_key,
)


@pytest.mark.parametrize('path,expected', [
    ('/api/health', 'api'),
    ('/api/history', 'api'),
    ('/api/detect', 'model'),
    ('/api/detect/', 'model'),
    ('/api/code/analyze', 'model'),
    ('/api/code/fix', 'model'),
    ('/api/doc/check', 'model'),
    ('/static/uploads/x.png', None),
    ('/docs', None),
    ('/', None),
])
def test_budget_selection(path, expected):
    assert budget_name(path) == expected


def test_forwarded_for_reads_the_last_hop():
    """Caddy appends the address it saw; earlier entries are client-supplied."""
    scope = {'headers': [(b'x-forwarded-for', b'1.2.3.4, 5.6.7.8')], 'client': ('127.0.0.1', 1)}
    assert client_key(scope) == '5.6.7.8'


def test_client_key_falls_back_to_the_socket_peer():
    assert client_key({'headers': [], 'client': ('10.0.0.9', 5)}) == '10.0.0.9'
    assert client_key({'headers': [], 'client': None}) == 'unknown'
    assert client_key({'headers': [(b'x-forwarded-for', b'  ')], 'client': ('10.0.0.9', 5)}) == '10.0.0.9'


def test_window_allows_up_to_the_limit_then_reports_a_delay():
    window = SlidingWindow(limit=2, window_seconds=10.0)
    assert window.retry_after('a', 0.0) is None
    assert window.retry_after('a', 1.0) is None
    blocked = window.retry_after('a', 2.0)
    assert blocked is not None and 8.0 <= blocked <= 10.0
    assert window.retry_after('b', 2.0) is None      # budgets are per client
    assert window.retry_after('a', 10.5) is None     # the oldest hit expired


def test_non_positive_limit_disables_the_window():
    assert SlidingWindow(limit=0, window_seconds=10.0).retry_after('a', 0.0) is None


def test_idle_keys_are_swept_so_state_stays_bounded():
    window = SlidingWindow(limit=1, window_seconds=1.0)
    window.retry_after('idle', 0.0)
    window.retry_after('fresh', 5.0)
    assert 'idle' not in window._hits
    assert 'fresh' in window._hits


def test_api_and_model_budgets_are_independent():
    limiter = RateLimiter(api_limit=1, api_window=60, model_limit=2, model_window=60)
    api_scope = {'path': '/api/history', 'headers': [], 'client': ('1.1.1.1', 0)}
    model_scope = {'path': '/api/detect', 'headers': [], 'client': ('1.1.1.1', 0)}
    assert limiter.retry_after(api_scope, 0.0) is None
    assert limiter.retry_after(api_scope, 0.1) is not None
    assert limiter.retry_after(model_scope, 0.2) is None
    assert limiter.retry_after(model_scope, 0.3) is None
    assert limiter.retry_after(model_scope, 0.4) is not None


def _app_with(limiter):
    app = FastAPI()
    app.add_middleware(RateLimitMiddleware, limiter=limiter)

    @app.get('/api/health')
    def health():
        return {'status': 'ok'}

    @app.get('/plain')
    def plain():
        return {'ok': True}

    return app


def _tight_limiter():
    return RateLimiter(api_limit=1, api_window=60, model_limit=1, model_window=60)


def test_over_budget_requests_get_429_with_a_retry_hint():
    client = TestClient(_app_with(_tight_limiter()))
    assert client.get('/api/health').status_code == 200
    blocked = client.get('/api/health')
    assert blocked.status_code == 429
    assert blocked.json()['detail'] == RATE_LIMITED_DETAIL
    assert int(blocked.headers['retry-after']) >= 1


def test_non_api_paths_are_never_budgeted():
    client = TestClient(_app_with(_tight_limiter()))
    for _ in range(5):
        assert client.get('/plain').status_code == 200


def test_limiter_errors_fail_open():
    class Broken:
        def retry_after(self, scope, now=None):
            raise RuntimeError('bookkeeping exploded')

    assert TestClient(_app_with(Broken())).get('/api/health').status_code == 200


def test_non_http_scopes_pass_through():
    """Lifespan and websocket scopes are not budgeted HTTP calls."""
    seen = []

    async def inner(scope, receive, send):
        seen.append(scope['type'])

    asyncio.run(RateLimitMiddleware(inner, _tight_limiter())({'type': 'lifespan'}, None, None))
    assert seen == ['lifespan']


def test_configured_budgets_cannot_block_a_realistic_demo():
    """A judged walkthrough is a handful of model calls, never a flood.

    This guards the shipped numbers themselves: a blocked demo is far worse than
    a stranger's wasted quota, so if someone lowers the ceilings into range of
    real work, this fails before the demo does.
    """
    limiter = RateLimiter(
        api_limit=main.settings.rate_limit_api_requests,
        api_window=main.settings.rate_limit_api_window_seconds,
        model_limit=main.settings.rate_limit_model_requests,
        model_window=main.settings.rate_limit_model_window_seconds,
    )
    model_scope = {'path': '/api/detect', 'headers': [], 'client': ('203.0.113.7', 0)}
    api_scope = {'path': '/api/history', 'headers': [], 'client': ('203.0.113.7', 0)}
    # Several back-to-back walkthroughs inside one window must all be served.
    assert all(limiter.retry_after(model_scope, float(second)) is None for second in range(30))
    # The dashboard polls /api/history and module-averages every five seconds.
    assert all(limiter.retry_after(api_scope, float(second)) is None for second in range(24))


def _middleware_names():
    return [middleware.cls.__name__ for middleware in main.app.user_middleware]


def test_real_app_wires_the_limiter_according_to_settings():
    assert ('RateLimitMiddleware' in _middleware_names()) == main.settings.rate_limit_enabled


def test_cors_wraps_the_limiter_so_429_replies_keep_cors_headers():
    names = _middleware_names()
    if 'RateLimitMiddleware' not in names:
        pytest.skip('rate limiting is disabled in this environment')
    assert names.index('CORSMiddleware') < names.index('RateLimitMiddleware')
