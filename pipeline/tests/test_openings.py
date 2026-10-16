import chess

from paperknight_pipeline import openings
from paperknight_pipeline.cli import main

SAMPLE = (
    "eco\tname\tpgn\n"
    "C20\tKing's Pawn Game\t1. e4 e5\n"
    "C50\tItalian Game\t1. e4 e5 2. Nf3 Nc6 3. Bc4\n"
    "C50\tItalian Game (transposed)\t1. e4 e5 2. Bc4 Nc6 3. Nf3\n"
)


def test_parse_keys_positions():
    rows = openings.parse(SAMPLE.splitlines())
    assert len(rows) == 3
    key, eco, name = rows[0]
    assert (eco, name) == ("C20", "King's Pawn Game")
    assert key == "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq"


def test_build_first_name_of_a_position_wins(tmp_path):
    out = tmp_path / "openings.tsv"
    assert openings.build([SAMPLE], out) == 2  # the transposition is the same position
    lines = out.read_text().splitlines()
    assert lines[0].startswith("#")
    italian = [l for l in lines if "\tC50\t" in l]
    assert italian and italian[0].endswith("\tItalian Game")


def test_key_ignores_en_passant():
    b = chess.Board()
    b.push_san("e4")
    assert openings.position_key(b) == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq"


def test_cli_local_input(tmp_path, capsys):
    src = tmp_path / "a.tsv"
    src.write_text(SAMPLE)
    out = tmp_path / "o.tsv"
    assert main(["openings", "--input", str(src), "--output", str(out)]) == 0
    assert "2 positions" in capsys.readouterr().out
