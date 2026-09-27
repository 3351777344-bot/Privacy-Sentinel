"""Per-client request budgets for the publicly reachable deployment.

The backend is reachable on the public internet without account authentication,
and three endpoints can spend the operator's paid model quota. A stranger who
finds the hostname can therefore drain that quota before a demo, so those paths
draw from a tighter budget than the rest of the API.

Three properties matter more than the exact numbers:

* A legitimate session must never be blocked. The default budgets sit far above
  real usage, every internal failure allows the request, and the whole feature
  can be switched off with ``GUARDIANHUB_RATE_LIMIT_ENABLED``.
* The client identity must not be forgeable. Requests arrive through the Caddy
  reverse proxy, so every socket comes from 127.0.0.1 and the real client only
  exists in ``X-Forwarded-For``. We read the *last* entry, because that is the
  address our single trusted proxy observed; earlier entries are client-supplied
  and reading one of those would let anyone bypass a budget by rotating a fake
  header.
* State stays bounded. Counters live in this process and idle keys are swept, so
  a long-running server cannot grow its memory without limit.
"""

from __future__ import annotations

import time
from collections import deque

from starlette.responses import JSONResponse

# Endpoints that may spend paid upstream model quota. Kept in sync with the
# places that construct an OpenAI client: /api/code/fix does it inline, while
# /api/detect and /api/code/analyze reach it through their detectors.
MODEL_PATHS = frozenset({"/api/detect", "/api/code/analyze", "/api/code/fix"})

RATE_LIMITED_DETAIL = "请求过于频繁，请稍后重试。"


def client_key(scope: dict) -> str:
    """Best-effort client identity used as the budget key."""
    for name, value in scope.get("headers") or ():
        if name == b"x-forwarded-for":
            hops = [hop.strip() for hop in value.decode("latin-1").split(",") if hop.strip()]
            if hops:
                return hops[-1]
    client = scope.get("client")
    if client:
        return str(client[0])
    return "unknown"


def budget_name(path: str) -> str | None:
    """Which budget a path draws from, or ``None`` when it is not limited."""
    if not path.startswith("/api/"):
        return None
    normalized = path.rstrip("/") or "/"
    return "model" if normalized in MODEL_PATHS else "api"


class SlidingWindow:
    """Hit counter per key over a rolling window."""

    def __init__(self, limit: int, window_seconds: float):
        self.limit = limit
        self.window = window_seconds
        self._hits: dict[str, deque] = {}
        self._last_sweep = 0.0

    def retry_after(self, key: str, now: float) -> float | None:
        """``None`` when the call fits the budget, else seconds until it would."""
        if self.limit <= 0 or self.window <= 0:
            return None
        hits = self._hits.setdefault(key, deque())
        cutoff = now - self.window
        while hits and hits[0] <= cutoff:
            hits.popleft()
        if len(hits) >= self.limit:
            return max(hits[0] + self.window - now, 0.0)
        hits.append(now)
        self._sweep(now, cutoff)
        return None

    def _sweep(self, now: float, cutoff: float) -> None:
        if now - self._last_sweep < self.window:
            return
        self._last_sweep = now
        for key in [k for k, hits in self._hits.items() if not hits or hits[-1] <= cutoff]:
            del self._hits[key]


class RateLimiter:
    """Applies the API-wide and model budgets to a single request."""

    def __init__(self, api_limit: int, api_window: float, model_limit: int, model_window: float):
        self._api = SlidingWindow(api_limit, api_window)
        self._model = SlidingWindow(model_limit, model_window)

    def retry_after(self, scope: dict, now: float | None = None) -> float | None:
        name = budget_name(scope.get("path", ""))
        if name is None:
            return None
        window = self._model if name == "model" else self._api
        return window.retry_after(client_key(scope), time.monotonic() if now is None else now)


class RateLimitMiddleware:
    """Rejects over-budget calls before they reach the application.

    Written as plain ASGI rather than ``BaseHTTPMiddleware`` so uploads and
    ``FileResponse`` downloads keep their original response objects.
    """

    def __init__(self, app, limiter: RateLimiter):
        self.app = app
        self.limiter = limiter

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return
        try:
            retry_after = self.limiter.retry_after(scope)
        except Exception:
            # Fail open: a bookkeeping bug must never take the API down.
            retry_after = None
        if retry_after is None:
            await self.app(scope, receive, send)
            return
        await JSONResponse(
            status_code=429,
            content={"detail": RATE_LIMITED_DETAIL},
            headers={"Retry-After": str(int(retry_after) + 1)},
        )(scope, receive, send)
