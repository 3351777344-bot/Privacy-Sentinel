"""Retry policy for external model calls.

A single model call can fail for two very different reasons, and the caller's
user-facing message depends on telling them apart:

* **Transient** — the request never got a verdict: the connection dropped, the
  read timed out, the provider returned 5xx, or it asked us to slow down. The
  same call is very likely to succeed a moment later, so one retry is free
  insurance. Without it a single hiccup costs the whole enhancement pass, and
  the user only sees "online analysis failed" for a failure that fixed itself.
* **Permanent** — bad credentials, missing model, a 4xx the provider will keep
  rejecting, or an answer we cannot parse. Retrying only burns the call budget
  and the client's patience, so these fail immediately.

Every failure carries a short human-readable reason (never a stack trace or
credential), which the detector copies into the response's internal diagnostics
field. The reason must never reach a user-facing message.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Any, Callable, TypeVar

logger = logging.getLogger(__name__)

T = TypeVar("T")

DEFAULT_ATTEMPTS = 2
DEFAULT_BACKOFF_SECONDS = 1.0

# HTTP statuses that mean "the call did not get a verdict", plus the local
# request error with no HTTP response at all.
_TRANSIENT_STATUSES = frozenset({408, 409, 425, 429, 500, 502, 503, 504})


@dataclass(frozen=True)
class ModelCallResult:
    """Outcome of one model call: the value, or why there is none.

    ``error`` is empty exactly when the call produced a usable ``value``.
    """

    value: Any = None
    error: str = ""


def _status_code(exc: BaseException) -> int | None:
    status = getattr(exc, "status_code", None)
    if isinstance(status, int):
        return status
    response = getattr(exc, "response", None)
    response_status = getattr(response, "status_code", None)
    return response_status if isinstance(response_status, int) else None


def _exception_class_name(exc: BaseException) -> str:
    return type(exc).__name__


def is_transient(exc: BaseException) -> bool:
    """True when retrying the same request has a real chance of succeeding."""
    status = _status_code(exc)
    if status is not None:
        return status in _TRANSIENT_STATUSES
    # No HTTP verdict at all: timeouts, dropped connections, TLS resets. These
    # surface as ``openai.APIConnectionError`` / ``APITimeoutError`` subclasses,
    # but the check stays on the class name so this module never needs the
    # provider SDK imported (and keeps working if it is missing).
    return any(
        token in _exception_class_name(exc)
        for token in ("Timeout", "Connection", "Connect")
    )


def describe_failure(exc: BaseException) -> str:
    """Short, log-friendly reason for a failed model call.

    Carries the exception class, the HTTP status when there was one, and a
    truncated provider body — enough to diagnose a rejection from the response
    alone, without echoing anything that could be a credential.
    """
    status = _status_code(exc)
    parts = [_exception_class_name(exc)]
    if status is not None:
        parts.append(f"HTTP {status}")
    message = str(exc).strip()
    if message:
        parts.append(message[:200])
    response = getattr(exc, "response", None)
    body = getattr(response, "text", None)
    if isinstance(body, str) and body.strip():
        parts.append(f"body={body.strip()[:200]}")
    return " | ".join(parts)


def call_with_retry(
    operation: Callable[[], T],
    *,
    label: str,
    attempts: int = DEFAULT_ATTEMPTS,
    backoff_seconds: float = DEFAULT_BACKOFF_SECONDS,
    sleep: Callable[[float], None] = time.sleep,
) -> ModelCallResult:
    """Run ``operation``, retrying transient failures at most ``attempts`` times.

    Never raises: the caller gets either the value or the reason, so a failed
    model call degrades to the local result instead of failing the request.
    """
    total = max(1, attempts)
    last_error = ""
    for attempt in range(1, total + 1):
        try:
            return ModelCallResult(value=operation())
        except Exception as exc:  # noqa: BLE001 - any provider failure degrades, none escapes
            last_error = describe_failure(exc)
            transient = is_transient(exc)
            logger.error(
                "%s failed (attempt %d/%d, transient=%s): %s",
                label,
                attempt,
                total,
                transient,
                last_error,
            )
            if not transient or attempt == total:
                break
            sleep(backoff_seconds * attempt)
    return ModelCallResult(value=None, error=last_error)
