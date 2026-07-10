import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path
from threading import Lock
from typing import Any, Iterator


class HistoryStore:
    def __init__(self, database_path: Path, legacy_json_path: Path | None = None) -> None:
        self.database_path = database_path
        self.legacy_json_path = legacy_json_path
        self._lock = Lock()
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS history (
                    record_id TEXT PRIMARY KEY,
                    module TEXT NOT NULL,
                    image_id TEXT NOT NULL DEFAULT '',
                    original_image_url TEXT NOT NULL DEFAULT '',
                    processed_image_url TEXT,
                    risk_level TEXT NOT NULL,
                    score INTEGER,
                    summary TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    status TEXT NOT NULL
                )
                """
            )
            columns = {row[1] for row in connection.execute("PRAGMA table_info(history)").fetchall()}
            if "score" not in columns:
                connection.execute("ALTER TABLE history ADD COLUMN score INTEGER")
            existing = connection.execute("SELECT COUNT(*) FROM history").fetchone()[0]
            if existing == 0:
                self._migrate_legacy_records(connection)

    def _migrate_legacy_records(self, connection: sqlite3.Connection) -> None:
        if not self.legacy_json_path or not self.legacy_json_path.exists():
            return
        try:
            records = json.loads(self.legacy_json_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return
        for record in records:
            self._insert(connection, self._normalize_record(record))

    @staticmethod
    def _normalize_record(record: dict[str, Any]) -> dict[str, Any]:
        image_id = str(record.get("imageId") or "")
        return {
            "recordId": str(record.get("recordId") or uuid.uuid4().hex),
            "module": str(record.get("module") or "privacy"),
            "imageId": image_id,
            "originalImageUrl": str(record.get("originalImageUrl") or ""),
            "processedImageUrl": record.get("processedImageUrl"),
            "riskLevel": str(record.get("riskLevel") or "low"),
            "score": record.get("score"),
            "summary": str(record.get("summary") or ""),
            "createdAt": str(record.get("createdAt") or datetime.now().astimezone().isoformat(timespec="seconds")),
            "status": str(record.get("status") or "已生成报告"),
        }

    @staticmethod
    def _insert(connection: sqlite3.Connection, record: dict[str, Any]) -> None:
        connection.execute(
            """
            INSERT OR REPLACE INTO history (
                record_id, module, image_id, original_image_url, processed_image_url,
                risk_level, score, summary, created_at, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                record["recordId"],
                record["module"],
                record["imageId"],
                record["originalImageUrl"],
                record["processedImageUrl"],
                record["riskLevel"],
                record["score"],
                record["summary"],
                record["createdAt"],
                record["status"],
            ),
        )

    def add(self, record: dict[str, Any]) -> dict[str, Any]:
        normalized = self._normalize_record(record)
        with self._lock, self._connect() as connection:
            self._insert(connection, normalized)
            connection.execute(
                """
                DELETE FROM history WHERE record_id NOT IN (
                    SELECT record_id FROM history ORDER BY created_at DESC, rowid DESC LIMIT 100
                )
                """
            )
        return normalized

    def list(self, limit: int = 20) -> list[dict[str, Any]]:
        safe_limit = max(1, min(limit, 100))
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM history ORDER BY created_at DESC, rowid DESC LIMIT ?", (safe_limit,)
            ).fetchall()
        return [self._row_to_record(row) for row in rows]

    def update_processed(self, image_id: str, processed_url: str) -> None:
        with self._lock, self._connect() as connection:
            connection.execute(
                """
                UPDATE history
                SET processed_image_url = ?, status = '已处理'
                WHERE image_id = ? AND module = 'privacy'
                """,
                (processed_url, image_id),
            )

    def delete_expired(self, retention_hours: int) -> None:
        if retention_hours <= 0:
            return
        cutoff = (datetime.now().astimezone() - timedelta(hours=retention_hours)).isoformat(timespec="seconds")
        with self._lock, self._connect() as connection:
            connection.execute("DELETE FROM history WHERE created_at < ?", (cutoff,))

    @staticmethod
    def _row_to_record(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "recordId": row["record_id"],
            "module": row["module"],
            "imageId": row["image_id"],
            "originalImageUrl": row["original_image_url"],
            "processedImageUrl": row["processed_image_url"],
            "riskLevel": row["risk_level"],
            "score": row["score"],
            "summary": row["summary"],
            "createdAt": row["created_at"],
            "status": row["status"],
        }
