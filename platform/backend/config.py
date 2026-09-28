import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


load_dotenv(Path(__file__).resolve().parent.parent / ".env")


def _repo_root() -> Path:
    """The checkout root this backend runs from (``platform/backend`` → repo)."""
    return Path(__file__).resolve().parent.parent.parent


def _detect_build_version() -> str:
    """What code is actually running, so ``/api/health`` can be trusted.

    The whole point of this field is to answer "is the deployment current?", and
    a hand-maintained answer cannot: it goes stale the first time someone pulls
    without editing it. That is not hypothetical — the first version of this
    field was read from ``GUARDIANHUB_BUILD_VERSION`` in ``.env``, and the
    deployed service reported the commit *before* the one it was running.

    So the commit is read from git, the only source that changes by itself.
    ``-dirty`` when the checkout has local modifications (a hand-patched server
    is a real deployment shape and must not look like a clean commit). The env
    var still wins when set, for deployments that ship without ``.git``.
    """
    override = _str_env("GUARDIANHUB_BUILD_VERSION")
    if override:
        return override
    try:
        described = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=_repo_root(),
            capture_output=True,
            text=True,
            timeout=5,
        )
        if described.returncode != 0:
            return "unknown"
        revision = described.stdout.strip()
        if not revision:
            return "unknown"
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=_repo_root(),
            capture_output=True,
            text=True,
            timeout=5,
        )
        dirty = status.returncode == 0 and status.stdout.strip()
        return f"{revision}-dirty" if dirty else revision
    except (OSError, subprocess.SubprocessError):
        # git missing, .git absent (tarball deployment), or the call timed out:
        # an unknown version must never stop the service from starting.
        return "unknown"


def _int_env(name: str, default: int) -> int:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    try:
        return int(raw_value)
    except ValueError:
        return default


def _bool_env(name: str, default: bool = False) -> bool:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


def _str_env(name: str, default: str = "") -> str:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    return raw_value.strip()


def _origins_env() -> tuple[str, ...]:
    raw_value = os.getenv("GUARDIANHUB_CORS_ORIGINS", "http://127.0.0.1:5173,http://localhost:5173")
    return tuple(origin.strip() for origin in raw_value.split(",") if origin.strip())


@dataclass(frozen=True)
class Settings:
    # Read from git, not from a hand-maintained variable: see _detect_build_version.
    build_version: str = _detect_build_version()
    cors_origins: tuple[str, ...] = _origins_env()
    max_image_bytes: int = _int_env("GUARDIANHUB_MAX_IMAGE_BYTES", 10 * 1024 * 1024)
    max_code_bytes: int = _int_env("GUARDIANHUB_MAX_CODE_BYTES", 1024 * 1024)
    max_code_archive_bytes: int = _int_env("GUARDIANHUB_MAX_CODE_ARCHIVE_BYTES", 10 * 1024 * 1024)
    max_code_uncompressed_bytes: int = _int_env("GUARDIANHUB_MAX_CODE_UNCOMPRESSED_BYTES", 50 * 1024 * 1024)
    max_code_archive_files: int = _int_env("GUARDIANHUB_MAX_CODE_ARCHIVE_FILES", 300)
    max_code_compression_ratio: int = _int_env("GUARDIANHUB_MAX_CODE_COMPRESSION_RATIO", 100)
    max_doc_bytes: int = _int_env("GUARDIANHUB_MAX_DOC_BYTES", 10 * 1024 * 1024)
    max_doc_total_bytes: int = _int_env("GUARDIANHUB_MAX_DOC_TOTAL_BYTES", 25 * 1024 * 1024)
    max_doc_files: int = _int_env("GUARDIANHUB_MAX_DOC_FILES", 8)
    max_image_pixels: int = _int_env("GUARDIANHUB_MAX_IMAGE_PIXELS", 25_000_000)
    retention_hours: int = _int_env("GUARDIANHUB_RETENTION_HOURS", 24)
    demo_mode: bool = _bool_env("GUARDIANHUB_DEMO_MODE")
    privacy_engine: str = os.getenv("GUARDIANHUB_PRIVACY_ENGINE", "agent").strip().lower()
    ocr_engine: str = os.getenv("GUARDIANHUB_OCR_ENGINE", "rapidocr").strip().lower()
    qr_engine: str = os.getenv("GUARDIANHUB_QR_ENGINE", "opencv").strip().lower()
    face_engine: str = os.getenv("GUARDIANHUB_FACE_ENGINE", "disabled").strip().lower()
    face_model_path: str = os.getenv("GUARDIANHUB_FACE_MODEL_PATH", "").strip()
    default_mask_type: str = os.getenv("GUARDIANHUB_DEFAULT_MASK_TYPE", "mosaic").strip().lower()
    enable_external_image_analysis: bool = _bool_env("GUARDIANHUB_ENABLE_EXTERNAL_IMAGE_ANALYSIS")
    code_engine: str = os.getenv("GUARDIANHUB_CODE_ENGINE", "deepseek").strip().lower()
    # DeepSeek V4.1 Flash covers text, code and vision, so it is the only
    # external model the backend needs. `deepseek-v4-flash` and
    # `deepseek-v4-flash-vision-exp` are retired names still served by this model.
    deepseek_api_key: str = _str_env("GUARDIANHUB_DEEPSEEK_API_KEY")
    deepseek_model: str = _str_env("GUARDIANHUB_DEEPSEEK_MODEL", "deepseek-flash")
    deepseek_vision_model: str = _str_env("GUARDIANHUB_DEEPSEEK_VISION_MODEL", "deepseek-flash")
    deepseek_api_base: str = _str_env("GUARDIANHUB_DEEPSEEK_API_BASE", "https://api.deepseek.com")
    deepseek_enabled: bool = _bool_env("GUARDIANHUB_DEEPSEEK_ENABLED")
    deepseek_timeout_seconds: int = _int_env("GUARDIANHUB_DEEPSEEK_TIMEOUT_SECONDS", 60)
    # Vision answers are JSON after the model's reasoning pass, so the ceiling has
    # to leave room for both: too small and the completion comes back empty with
    # finish_reason=length.
    deepseek_max_tokens: int = _int_env("GUARDIANHUB_DEEPSEEK_MAX_TOKENS", 8192)
    # Doc Shield's online pass reads a pasted brief and then the extracted
    # material text. Both are excerpts by design: the brief is a short notice,
    # and a whole thesis would both overflow the context and send far more of the
    # student's writing to the model than the check needs. The local word-count
    # and privacy checks still run over the full text, so truncation only limits
    # what the model *reads*, never what the report measures.
    doc_content_chars_per_file: int = _int_env("GUARDIANHUB_DOC_CONTENT_CHARS_PER_FILE", 6000)
    doc_content_chars_total: int = _int_env("GUARDIANHUB_DOC_CONTENT_CHARS_TOTAL", 12000)
    vision_image_max_side: int = _int_env("GUARDIANHUB_VISION_IMAGE_MAX_SIDE", 1280)
    # Per-client request budgets. The public deployment has no account
    # authentication and three endpoints can spend paid model quota, so those
    # paths draw from a tighter budget than the rest of the API.
    #
    # These ceilings exist to stop automated flooding, not to meter real work,
    # and they are deliberately set orders of magnitude above a judged demo: a
    # full walkthrough of the four modules costs 2-6 model calls in five
    # minutes, and the busiest legitimate client is the dashboard polling
    # /api/history twice every five seconds (24 requests a minute). A blocked
    # demo would be far worse than a stranger's wasted quota, so the numbers
    # only need to catch a script hammering the endpoints. Set a limit to 0 to
    # drop that budget, or set GUARDIANHUB_RATE_LIMIT_ENABLED=false to disable
    # the feature entirely.
    rate_limit_enabled: bool = _bool_env("GUARDIANHUB_RATE_LIMIT_ENABLED", True)
    rate_limit_api_requests: int = _int_env("GUARDIANHUB_RATE_LIMIT_API_REQUESTS", 600)
    rate_limit_api_window_seconds: int = _int_env("GUARDIANHUB_RATE_LIMIT_API_WINDOW_SECONDS", 60)
    rate_limit_model_requests: int = _int_env("GUARDIANHUB_RATE_LIMIT_MODEL_REQUESTS", 120)
    rate_limit_model_window_seconds: int = _int_env("GUARDIANHUB_RATE_LIMIT_MODEL_WINDOW_SECONDS", 300)


settings = Settings()
