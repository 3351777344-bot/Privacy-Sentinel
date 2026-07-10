import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


load_dotenv(Path(__file__).resolve().parent.parent / ".env")


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


def _origins_env() -> tuple[str, ...]:
    raw_value = os.getenv("GUARDIANHUB_CORS_ORIGINS", "http://127.0.0.1:5173,http://localhost:5173")
    return tuple(origin.strip() for origin in raw_value.split(",") if origin.strip())


@dataclass(frozen=True)
class Settings:
    cors_origins: tuple[str, ...] = _origins_env()
    max_image_bytes: int = _int_env("GUARDIANHUB_MAX_IMAGE_BYTES", 10 * 1024 * 1024)
    max_code_bytes: int = _int_env("GUARDIANHUB_MAX_CODE_BYTES", 1024 * 1024)
    max_doc_bytes: int = _int_env("GUARDIANHUB_MAX_DOC_BYTES", 10 * 1024 * 1024)
    max_doc_total_bytes: int = _int_env("GUARDIANHUB_MAX_DOC_TOTAL_BYTES", 25 * 1024 * 1024)
    max_doc_files: int = _int_env("GUARDIANHUB_MAX_DOC_FILES", 8)
    max_image_pixels: int = _int_env("GUARDIANHUB_MAX_IMAGE_PIXELS", 25_000_000)
    retention_hours: int = _int_env("GUARDIANHUB_RETENTION_HOURS", 24)
    demo_mode: bool = _bool_env("GUARDIANHUB_DEMO_MODE")


settings = Settings()
