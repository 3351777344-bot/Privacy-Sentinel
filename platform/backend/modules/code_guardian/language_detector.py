from pathlib import Path


EXTENSION_LANGUAGE_MAP = {
    ".py": "python",
    ".java": "java",
    ".js": "javascript",
    ".ts": "typescript",
    ".sql": "sql",
    ".txt": "other",
}

SUPPORTED_LANGUAGES = {"python", "java", "javascript", "typescript", "sql", "other"}


def normalize_language(language: str | None, filename: str | None = None) -> str:
    selected = (language or "").strip().lower()
    aliases = {
        "js": "javascript",
        "javascript / typescript": "typescript",
        "javascript/typescript": "typescript",
        "ts": "typescript",
        "other": "other",
        "": "",
    }
    selected = aliases.get(selected, selected)
    if selected in SUPPORTED_LANGUAGES:
        return selected

    suffix = Path(filename or "").suffix.lower()
    return EXTENSION_LANGUAGE_MAP.get(suffix, "other")

