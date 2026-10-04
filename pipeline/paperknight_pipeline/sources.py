"""Download and open public datasets, cached in build/downloads/ (see docs/data-sources.md)."""
from __future__ import annotations

import io
import shutil
import urllib.request
from pathlib import Path
from typing import IO

import zstandard

LICHESS_PUZZLES_URL = "https://database.lichess.org/lichess_db_puzzle.csv.zst"


def download(url: str, dest_dir: Path, force: bool = False) -> Path:
    """Download `url` into `dest_dir` unless already cached. Returns the local path."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / url.rsplit("/", 1)[-1]
    if dest.exists() and not force:
        return dest
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "paperknight-pipeline"})
    with urllib.request.urlopen(req, timeout=60) as resp, open(tmp, "wb") as out:
        expected = resp.headers.get("Content-Length")
        shutil.copyfileobj(resp, out, length=1 << 20)
    size = tmp.stat().st_size
    if expected is not None and size != int(expected):
        tmp.unlink()
        raise IOError(f"truncated download of {url}: {size} of {expected} bytes")
    tmp.rename(dest)
    return dest


def open_text(path: Path) -> IO[str]:
    """Open a plain or .zst-compressed text file for streaming reads."""
    if path.suffix == ".zst":
        raw = open(path, "rb")
        stream = zstandard.ZstdDecompressor().stream_reader(raw, closefd=True)
        return io.TextIOWrapper(stream, encoding="utf-8", newline="")
    return open(path, encoding="utf-8", newline="")
