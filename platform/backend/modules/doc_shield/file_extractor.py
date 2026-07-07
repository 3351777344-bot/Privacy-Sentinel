from dataclasses import dataclass
from io import BytesIO
from pathlib import Path


@dataclass
class ExtractedFile:
    fileName: str
    extension: str
    contentType: str
    size: int
    text: str
    status: str
    wordCount: int
    pageCount: int | None = None
    error: str | None = None


def _decode_text(content: bytes) -> str:
    for encoding in ("utf-8", "utf-8-sig", "gb18030"):
        try:
            return content.decode(encoding)
        except UnicodeDecodeError:
            continue
    return content.decode("utf-8", errors="ignore")


def _word_count(text: str) -> int:
    chinese_chars = len([char for char in text if "\u4e00" <= char <= "\u9fff"])
    latin_words = len([part for part in text.replace("\n", " ").split(" ") if part.strip()])
    return max(chinese_chars, latin_words)


def extract_file(file_name: str, content_type: str | None, content: bytes) -> ExtractedFile:
    suffix = Path(file_name).suffix.lower().lstrip(".")
    text = ""
    status = "metadata_only"
    page_count: int | None = None
    error: str | None = None

    try:
        if suffix in {"txt", "md"}:
            text = _decode_text(content)
            status = "parsed"
        elif suffix == "pdf":
            try:
                from pypdf import PdfReader

                reader = PdfReader(BytesIO(content))
                page_count = len(reader.pages)
                text = "\n".join(page.extract_text() or "" for page in reader.pages)
                status = "parsed" if text.strip() else "metadata_only"
            except Exception as exc:  # PDF parsing should not block file-level checks.
                status = "parse_failed"
                error = f"PDF 内容解析失败：{exc}"
        elif suffix == "docx":
            try:
                from docx import Document

                document = Document(BytesIO(content))
                text = "\n".join(paragraph.text for paragraph in document.paragraphs)
                status = "parsed" if text.strip() else "metadata_only"
            except Exception as exc:
                status = "parse_failed"
                error = f"DOCX 内容解析失败：{exc}"
    except Exception as exc:
        status = "parse_failed"
        error = f"文件读取失败：{exc}"

    return ExtractedFile(
        fileName=file_name,
        extension=suffix,
        contentType=content_type or "application/octet-stream",
        size=len(content),
        text=text,
        status=status,
        wordCount=_word_count(text),
        pageCount=page_count,
        error=error,
    )
