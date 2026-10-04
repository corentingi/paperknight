from pathlib import Path

import pytest

from paperknight_pipeline import studies
from paperknight_pipeline.cli import main

FIXTURE = Path(__file__).resolve().parents[2] / "plugin" / "tests" / "fixtures" / "study.pgn"


@pytest.mark.parametrize("text", [
    "Xk3pQ7aZ",
    "https://lichess.org/study/Xk3pQ7aZ",
    "https://lichess.org/study/Xk3pQ7aZ/Lm9TfR2c",
    "lichess.org/study/Xk3pQ7aZ?foo=1",
])
def test_parse_study_id(text):
    assert studies.parse_study_id(text) == "Xk3pQ7aZ"


@pytest.mark.parametrize("text", ["", "short", "https://lichess.org/abcdefgh12"])
def test_parse_study_id_rejects(text):
    with pytest.raises(ValueError):
        studies.parse_study_id(text)


def test_validate_fixture():
    report = studies.validate(FIXTURE.read_text())
    assert report.name == "Paperknight test study"
    assert report.chapters == 5 and report.gamebook_chapters == 1
    assert report.moves == 21 + 6 + 7 + 0 + 6
    assert report.problems == []


def test_validate_reports_illegal_moves():
    report = studies.validate('[Event "x"]\n\n1. e4 e5 2. Ke3 *\n')
    assert report.chapters == 1 and report.problems and "Ke3" in report.problems[0]


def test_download_sends_token_and_flags(monkeypatch):
    seen = {}

    class Resp:
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def read(self): return b'[Event "x"]\n\n1. e4 *\n'

    def fake_urlopen(req, timeout):
        seen["url"], seen["auth"] = req.full_url, req.get_header("Authorization")
        return Resp()

    monkeypatch.setattr(studies.urllib.request, "urlopen", fake_urlopen)
    assert studies.download_study("Xk3pQ7aZ", token="tok").startswith("[Event")
    assert "orientation=true" in seen["url"] and "clocks=false" in seen["url"]
    assert seen["auth"] == "Bearer tok"


def test_cli_study_http_error_hint(monkeypatch, capsys):
    import urllib.error

    def fail(*a, **k):
        raise urllib.error.HTTPError("u", 404, "Not Found", {}, None)

    monkeypatch.setattr(studies, "download_study", fail)
    assert main(["study", "Xk3pQ7aZ"]) == 1
    assert "private study?" in capsys.readouterr().err


def test_cli_study_from_local_file(tmp_path, capsys):
    code = main(["study", "Xk3pQ7aZ", "--input", str(FIXTURE), "--output-dir", str(tmp_path)])
    assert code == 0
    out = tmp_path / "paperknight-test-study-Xk3pQ7aZ.pgn"
    assert out.read_text() == FIXTURE.read_text()
    assert "5 chapters (1 interactive)" in capsys.readouterr().out
