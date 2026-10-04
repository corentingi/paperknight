"""Shared helpers for writing packs (see docs/pack-format.md)."""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def create_pack(path: Path, kind: str, format_version: int, source: str, license: str) -> sqlite3.Connection:
    """Create an empty pack at `path` (replacing any existing file) with its meta table."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    conn.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        [
            ("format_version", str(format_version)),
            ("kind", kind),
            ("built_at", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")),
            ("source", source),
            ("license", license),
        ],
    )
    return conn


def finalize_pack(conn: sqlite3.Connection, extra_meta: dict[str, str] | None = None) -> None:
    """Write extra meta, compact the file and close it."""
    if extra_meta:
        conn.executemany("INSERT INTO meta (key, value) VALUES (?, ?)", list(extra_meta.items()))
    conn.commit()
    conn.execute("VACUUM")
    conn.close()
