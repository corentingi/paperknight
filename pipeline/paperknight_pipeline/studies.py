"""Download a Lichess study as PGN and validate it (ADR-0011, docs/studies.md).

Studies are read directly by the plugin; this command only fetches the export
with the right flags and reports problems before the file goes to the device.
"""
from __future__ import annotations

import io
import os
import re
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import chess.pgn

EXPORT_URL = "https://lichess.org/api/study/{id}.pgn?orientation=true&clocks=false&comments=true&variations=true"
STUDY_ID = re.compile(
    r"(?:(?:https?://)?(?:www\.)?lichess\.org/study/)?([A-Za-z0-9]{8})(?:[/?#].*)?")


def parse_study_id(text: str) -> str:
    """Accepts an 8-character id or a lichess.org/study/<id>[/<chapter>] URL."""
    m = STUDY_ID.fullmatch(text.strip())
    if not m:
        raise ValueError(f"not a Lichess study id or URL: {text!r}")
    return m.group(1)


def download_study(study_id: str, token: str | None = None, timeout: int = 60) -> str:
    """Returns the study PGN. A token (scope study:read) is needed for private studies."""
    req = urllib.request.Request(EXPORT_URL.format(id=study_id),
                                 headers={"User-Agent": "paperknight-pipeline"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")


@dataclass
class Report:
    name: str
    chapters: int = 0
    gamebook_chapters: int = 0
    moves: int = 0
    problems: list[str] = field(default_factory=list)


def validate(pgn: str) -> Report:
    """Parses every chapter with python-chess; illegal moves become problems (not fatal)."""
    stream = io.StringIO(pgn)
    report = Report(name="")
    while (game := chess.pgn.read_game(stream)) is not None:
        report.chapters += 1
        headers = game.headers
        report.name = report.name or headers.get("StudyName", "")
        if headers.get("ChapterMode") == "gamebook":
            report.gamebook_chapters += 1

        def count(node: chess.pgn.GameNode) -> int:
            return sum(1 + count(child) for child in node.variations)

        report.moves += count(game)
        title = headers.get("ChapterName") or headers.get("Event", f"chapter {report.chapters}")
        for err in game.errors:
            report.problems.append(f"chapter {report.chapters} ({title}): {err}")
    return report


def slug(text: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-").lower()
    return s or "study"


def save(pgn: str, out_dir: Path, name: str, study_id: str) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{slug(name)}-{study_id}.pgn"
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(pgn, encoding="utf-8")
    os.replace(tmp, path)
    return path
