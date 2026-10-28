"""Resumable downloads (sources.download) against a local HTTP server."""
from __future__ import annotations

import http.server
import threading
import urllib.error
from pathlib import Path

import pytest

from paperknight_pipeline import sources

DATA = bytes(range(256)) * 4096  # 1 MiB


class Server:
    """Serves DATA at /data.bin. `drop_after`: byte counts at which the next
    responses are cut (one per request). `ranges`: honour Range headers."""

    def __init__(self, drop_after=(), ranges=True, status=200, etag=None):
        self.drop_after = list(drop_after)
        self.ranges = ranges
        self.status = status
        self.etag = etag  # sent as ETag; an If-Range that differs gets the whole file
        self.data = DATA
        self.if_ranges = []
        self.requests = []
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                rng = self.headers.get("Range")
                outer.requests.append(rng)
                if_range = self.headers.get("If-Range")
                outer.if_ranges.append(if_range)
                if if_range is not None and if_range != outer.etag:
                    rng = None  # the file changed: whole new body
                data = outer.data
                if outer.status != 200:
                    self.send_error(outer.status)
                    return
                start = 0
                if rng and outer.ranges:
                    start = int(rng.split("=")[1].split("-")[0])
                    if start >= len(data):
                        self.send_response(416)
                        self.send_header("Content-Range", f"bytes */{len(data)}")
                        self.end_headers()
                        return
                    self.send_response(206)
                    self.send_header("Content-Range", f"bytes {start}-{len(data) - 1}/{len(data)}")
                else:
                    self.send_response(200)
                if outer.etag:
                    self.send_header("ETag", outer.etag)
                body = data[start:]
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                cut = outer.drop_after.pop(0) if outer.drop_after else None
                self.wfile.write(body if cut is None else body[:cut])
                self.wfile.flush()
                if cut is not None:
                    self.close_connection = True

        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}/data.bin"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


@pytest.fixture
def server(request):
    servers = []

    def make(**kw):
        s = Server(**kw)
        servers.append(s)
        return s

    yield make
    for s in servers:
        s.close()


def fetch(url: str, tmp_path: Path, **kw) -> Path:
    return sources.download(url, tmp_path, backoff=0, timeout=5, **kw)


def test_plain_download(server, tmp_path):
    s = server()
    path = fetch(s.url, tmp_path)
    assert path.read_bytes() == DATA
    assert not (tmp_path / "data.bin.part").exists()
    assert fetch(s.url, tmp_path) == path and len(s.requests) == 1, "cached"


def test_broken_transfers_are_resumed(server, tmp_path):
    s = server(drop_after=[300_000, 200_000])
    assert fetch(s.url, tmp_path).read_bytes() == DATA
    assert s.requests == [None, "bytes=300000-", "bytes=500000-"]


def test_a_part_file_from_an_earlier_run_is_resumed(server, tmp_path):
    (tmp_path / "data.bin.part").write_bytes(DATA[:123_456])
    s = server()
    assert fetch(s.url, tmp_path).read_bytes() == DATA
    assert s.requests == ["bytes=123456-"]


def test_a_complete_part_file_is_finished(server, tmp_path):
    (tmp_path / "data.bin.part").write_bytes(DATA)
    s = server()
    assert fetch(s.url, tmp_path).read_bytes() == DATA


def test_a_server_without_ranges_restarts_the_file(server, tmp_path):
    (tmp_path / "data.bin.part").write_bytes(b"x" * 1000)
    s = server(ranges=False, drop_after=[100_000])
    assert fetch(s.url, tmp_path).read_bytes() == DATA, "old bytes not kept"


def test_gives_up_after_the_retries(server, tmp_path):
    s = server(drop_after=[10] * 10)
    with pytest.raises(IOError, match="after 2 retries"):
        fetch(s.url, tmp_path, retries=2)
    assert len(s.requests) == 3
    assert (tmp_path / "data.bin.part").exists(), "kept for the next run"


def test_client_errors_are_not_retried(server, tmp_path):
    s = server(status=404)
    with pytest.raises(urllib.error.HTTPError):
        fetch(s.url, tmp_path)
    assert len(s.requests) == 1


def test_force_downloads_again(server, tmp_path):
    (tmp_path / "data.bin").write_bytes(b"old")
    (tmp_path / "data.bin.part").write_bytes(b"stale")
    s = server()
    assert fetch(s.url, tmp_path, force=True).read_bytes() == DATA
    assert s.requests == [None]


def test_resume_sends_if_range_and_keeps_the_same_file(server, tmp_path):
    s = server(drop_after=[300_000], etag='"v1"')
    path = fetch(s.url, tmp_path)
    assert path.read_bytes() == DATA
    assert s.if_ranges == [None, '"v1"'], "the resume asks for the same version"
    assert not (tmp_path / "data.bin.part.validator").exists(), "validator removed once complete"


def test_a_file_changed_on_the_server_restarts_instead_of_appending(server, tmp_path):
    s = server(drop_after=[300_000], etag='"v1"')
    with pytest.raises(IOError):
        sources.download(s.url, tmp_path, retries=0, backoff=0)
    # next month's dump: different bytes, new ETag
    s.etag, s.data = '"v2"', bytes(reversed(DATA))
    path = sources.download(s.url, tmp_path, retries=0, backoff=0)
    assert path.read_bytes() == s.data, "the new file, not old start + new end"


def _lines(n: int) -> bytes:
    return "".join(f"{i},a line of the file\n" for i in range(n)).encode()


def test_zst_files_are_read_across_frames(tmp_path):
    import zstandard
    c = zstandard.ZstdCompressor()
    path = tmp_path / "two-frames.csv.zst"
    path.write_bytes(c.compress(_lines(50000)) + c.compress(b"last\n"))
    with sources.open_text(path) as f:
        lines = f.read().splitlines()
    assert len(lines) == 50001 and lines[0] == "0,a line of the file" and lines[-1] == "last"


def test_a_truncated_zst_file_raises(tmp_path):
    import zstandard
    data = zstandard.ZstdCompressor().compress(_lines(50000))
    path = tmp_path / "cut.csv.zst"
    path.write_bytes(data[: len(data) // 2])
    with pytest.raises(IOError, match="truncated"):
        with sources.open_text(path) as f:
            for _line in f:
                pass
