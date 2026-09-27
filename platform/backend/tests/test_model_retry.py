"""Contracts for the retry policy around external model calls.

Two invariants matter and are both enforced here:

1. A transient failure (no verdict from the provider) gets exactly one retry,
   because that is what turned a self-healing hiccup into a user-visible
   "online analysis failed".
2. A permanent failure (bad credentials, a 4xx the provider will keep
   rejecting, an unparseable answer) is NOT retried — that only spends quota
   twice and delays the honest fallback.
"""
from __future__ import annotations

import pytest

from model_retry import ModelCallResult, call_with_retry, describe_failure, is_transient


class _FakeHTTPError(Exception):
    """Stands in for an SDK error carrying an HTTP status."""

    def __init__(self, status_code: int, message: str = "provider rejected the request") -> None:
        super().__init__(message)
        self.status_code = status_code


class _FakeConnectionError(Exception):
    """The classifier reads the exception class name, so the SDK naming is mirrored."""


_FakeConnectionError.__name__ = "APIConnectionError"
_FakeConnectionError.__qualname__ = "APIConnectionError"


def _sleep_recorder() -> tuple[list[float], object]:
    waits: list[float] = []
    return waits, lambda seconds: waits.append(seconds)


def test_transient_failure_is_retried_once_and_can_succeed() -> None:
    attempts: list[int] = []
    waits, sleep = _sleep_recorder()

    def operation() -> str:
        attempts.append(len(attempts) + 1)
        if len(attempts) == 1:
            raise TimeoutError("read timed out")
        return "recovered"

    result = call_with_retry(operation, label="test call", sleep=sleep)

    assert result == ModelCallResult(value="recovered")
    assert len(attempts) == 2
    # Backoff must wait before the retry, not hammer the provider immediately.
    assert waits == [1.0]


def test_permanent_failure_is_not_retried() -> None:
    attempts: list[int] = []
    waits, sleep = _sleep_recorder()

    def operation() -> str:
        attempts.append(1)
        raise _FakeHTTPError(401, "invalid api key")

    result = call_with_retry(operation, label="test call", sleep=sleep)

    assert result.value is None
    assert "401" in result.error
    assert len(attempts) == 1
    assert waits == []


def test_transient_failure_gives_up_after_the_attempt_budget() -> None:
    attempts: list[int] = []
    waits, sleep = _sleep_recorder()

    def operation() -> str:
        attempts.append(1)
        raise _FakeHTTPError(503, "provider unavailable")

    result = call_with_retry(operation, label="test call", attempts=3, sleep=sleep)

    assert result.value is None
    assert "503" in result.error
    assert len(attempts) == 3
    # Waits grow linearly; the final failure does not sleep.
    assert waits == [1.0, 2.0]


@pytest.mark.parametrize(
    ("error", "transient"),
    [
        (_FakeHTTPError(429, "slow down"), True),
        (_FakeHTTPError(500, "boom"), True),
        (_FakeHTTPError(400, "bad request"), False),
        (_FakeHTTPError(401, "unauthorized"), False),
        (_FakeHTTPError(404, "no such model"), False),
        (TimeoutError("read timed out"), True),
        (_FakeConnectionError("connection reset"), True),
        (ValueError("cannot parse"), False),
    ],
)
def test_failure_classification(error: Exception, transient: bool) -> None:
    assert is_transient(error) is transient


def test_describe_failure_keeps_the_provider_verdict() -> None:
    class _Response:
        status_code = 403
        text = "model does not support image input"

    class _ProviderError(Exception):
        response = _Response()

    described = describe_failure(_ProviderError("forbidden"))

    assert "_ProviderError" in described
    assert "HTTP 403" in described
    assert "model does not support image input" in described


def test_describe_failure_truncates_a_long_body() -> None:
    class _ProviderError(Exception):
        pass

    described = describe_failure(_ProviderError("x" * 500))

    assert len(described) < 400
    assert described.endswith("x" * 10)
