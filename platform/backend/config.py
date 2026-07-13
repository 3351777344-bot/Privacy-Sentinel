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
    cors_origins: tuple[str, ...] = _origins_env()
    max_image_bytes: int = _int_env("GUARDIANHUB_MAX_IMAGE_BYTES", 10 * 1024 * 1024)
    max_code_bytes: int = _int_env("GUARDIANHUB_MAX_CODE_BYTES", 1024 * 1024)
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
    qwen_api_key: str = _str_env("GUARDIANHUB_QWEN_API_KEY")
    qwen_model: str = _str_env("GUARDIANHUB_QWEN_MODEL", "qwen3.6-flash-2026-04-16")
    qwen_api_base: str = _str_env("GUARDIANHUB_QWEN_API_BASE", "https://dashscope.aliyuncs.com/compatible-mode/v1")
    qwen_enabled: bool = _bool_env("GUARDIANHUB_QWEN_ENABLED")


settings = Settings()
