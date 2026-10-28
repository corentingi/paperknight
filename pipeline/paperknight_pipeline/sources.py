"""Download and open public datasets, cached in build/downloads/ (see docs/data-sources.md)."""
from __future__ import annotations

import http.client
import io
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import IO

import zstandard

LICHESS_PUZZLES_URL = "https://database.lichess.org/lichess_db_puzzle.csv.zst"


CHUNK = 1 << 20


def download(url: str, dest_dir: Path, force: bool = False, retries: int = 5,
             backoff: float = 2.0, timeout: int = 60) -> Path:
    """Download `url` into `dest_dir` unless already cached. Returns the local path.

    The file is written to `<name>.part` and renamed when complete. A broken
    transfer is resumed with an HTTP Range request, up to `retries` times
    (waiting backoff, 2*backoff, ...); a `.part` left by an earlier run is
    resumed too. A server that ignores Range restarts the file from scratch.
    The server's validator (ETag, else Last-Modified) is kept next to the
    `.part` and sent as If-Range: if the file changed on the server since
    (Lichess publishes a new dump monthly), it sends the whole new file
    instead of appending its end to the old start.
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / url.rsplit("/", 1)[-1]
    if dest.exists() and not force:
        return dest
    tmp = dest.with_suffix(dest.suffix + ".part")
    if force:
        for stale in (tmp, _validator_path(tmp)):
            if stale.exists():
                stale.unlink()
    failures = 0
    while True:
        try:
            total = _fetch(url, tmp, timeout)
            break
        except (urllib.error.URLError, http.client.HTTPException, OSError) as err:
            if isinstance(err, urllib.error.HTTPError) and err.code < 500 and err.code != 416:
                raise  # 404 and such: retrying will not help
            failures += 1
            if failures > retries:
                raise IOError(f"download of {url} failed after {retries} retries: {err}") from err
            wait = backoff * 2 ** (failures - 1)
            print(f"download interrupted ({err}); resuming in {wait:.0f} s", file=sys.stderr)
            time.sleep(wait)
    size = tmp.stat().st_size
    if total is not None and size != total:
        raise IOError(f"truncated download of {url}: {size} of {total} bytes")
    tmp.rename(dest)
    if _validator_path(tmp).exists():
        _validator_path(tmp).unlink()
    return dest


def _validator_path(tmp: Path) -> Path:
    return tmp.with_suffix(tmp.suffix + ".validator")


def _fetch(url: str, tmp: Path, timeout: int) -> int | None:
    """Appends the rest of `url` to `tmp`. Returns the full size if known.

    Raises on a broken transfer, leaving what was received in `tmp`.
    """
    have = tmp.stat().st_size if tmp.exists() else 0
    req = urllib.request.Request(url, headers={"User-Agent": "paperknight-pipeline"})
    validator_file = _validator_path(tmp)
    if have:
        req.add_header("Range", f"bytes={have}-")
        if validator_file.exists():  # resume only the same version of the file
            req.add_header("If-Range", validator_file.read_text())
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as err:
        if err.code == 416 and have:  # nothing left to fetch, or a stale .part
            total = _range_total(err.headers.get("Content-Range"))
            if total == have:
                return total
            tmp.unlink()
        raise
    with resp:
        if have and resp.status == 206:
            total = _range_total(resp.headers.get("Content-Range"))
            mode = "ab"
        else:  # full body (first request, no Range support, or a changed file): start over
            length = resp.headers.get("Content-Length")
            total = int(length) if length is not None else None
            mode = "wb"
            validator = resp.headers.get("ETag") or resp.headers.get("Last-Modified")
            if validator:
                validator_file.write_text(validator)
            elif validator_file.exists():
                validator_file.unlink()
        with open(tmp, mode) as out:
            while chunk := resp.read(CHUNK):
                out.write(chunk)
    size = tmp.stat().st_size
    if total is not None and size < total:
        raise http.client.IncompleteRead(b"", total - size)
    return total


def _range_total(content_range: str | None) -> int | None:
    m = re.match(r"bytes (?:\d+-\d+|\*)/(\d+)", content_range or "")
    return int(m.group(1)) if m else None


class _ZstdReader(io.RawIOBase):
    """Decompresses a .zst file frame after frame, and raises at its end if
    the last frame is cut (zstandard's stream_reader just stops there: a
    truncated cached file would give part of the data without an error)."""

    CHUNK = 1 << 17

    def __init__(self, path: Path):
        self._raw = open(path, "rb")
        self._path = path
        self._decompressor = zstandard.ZstdDecompressor()
        self._frame = None  # the frame being decompressed
        self._out = memoryview(b"")

    def readable(self) -> bool:
        return True

    def readinto(self, buffer) -> int:
        while not self._out:
            chunk = self._raw.read(self.CHUNK)
            if not chunk:
                if self._frame is not None:
                    raise IOError(f"{self._path}: truncated .zst file")
                return 0
            out = []
            while chunk:
                if self._frame is None:
                    self._frame = self._decompressor.decompressobj()
                out.append(self._frame.decompress(chunk))
                chunk = b""
                if self._frame.eof:
                    chunk, self._frame = self._frame.unused_data, None
            self._out = memoryview(b"".join(out))
        n = min(len(buffer), len(self._out))
        buffer[:n] = self._out[:n]
        self._out = self._out[n:]
        return n

    def close(self) -> None:
        self._raw.close()
        super().close()


def open_text(path: Path) -> IO[str]:
    """Open a plain or .zst-compressed text file for streaming reads. A
    truncated .zst file raises IOError at its end; a damaged one raises
    zstandard.ZstdError when its frames carry a checksum (zstd's default)."""
    if path.suffix == ".zst":
        stream = io.BufferedReader(_ZstdReader(path), buffer_size=_ZstdReader.CHUNK)
        return io.TextIOWrapper(stream, encoding="utf-8", newline="")
    return open(path, encoding="utf-8", newline="")
