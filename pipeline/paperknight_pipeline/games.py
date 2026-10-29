"""Master games for Guess the move (ADR-0021, docs/games.md).

The games are listed in `pipeline/data/master-games.tsv` (our choice, our
notes); their moves come from PGN Mentor's player files (moves are facts).
Stockfish then looks at every position, from the side to move's point of
view: its three best moves and their scores, and the score of the move
played when it is not among them. Key moments are the positions where the
master found the only good move. The plugin's `data/games.tsv` holds it all,
one game a line:

    id  title  white  black  event  site  year  round  result  note  book  moves  analysis

`book`: the plies played from the start through the last named opening
position (data/openings.tsv); guessing starts after them. `moves`: UCI,
space-separated. `analysis`: one entry a ply, space-separated; an entry is
`move:score` pairs separated by commas (best first, then the move played
if Stockfish did not list it), with a `!` in front for a key moment; `-`
for the book plies (not analysed). A
score is in centipawns for the side to move; a mate is 10000 minus ten per
move (mated: the negative).
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import time
import unicodedata
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable

import chess
import chess.engine
import chess.pgn

PGNMENTOR_URL = "https://www.pgnmentor.com/players/{}.zip"
USER_AGENT = "paperknight-pipeline (+https://github.com/corentingi/paperknight)"
MATE = 10000

HEADER = ("# Master games for Guess the move (ADR-0021): id, title, white, black, event, site,"
          " year, round, result, note, book plies, moves (UCI), analysis (Stockfish, per ply:"
          " move:centipawns for the side to move, best first; ! = key moment). Moves from"
          " PGN Mentor (pgnmentor.com); built by `python -m paperknight_pipeline games`.\n")

# a key moment: the master's move is (nearly) the best and every other move
# is clearly worse, in winning chances (Lichess's scale, below)
KEY_GAP = 15        # points of winning chances between the move and the next best
KEY_NEAR_BEST = 3   # the master's move within this of the best


def win(cp: int) -> float:
    """Winning chances (0-100) of a score in centipawns, as Lichess counts them."""
    import math
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)


@dataclass
class Seed:
    id: str
    source: str
    white: str
    black: str
    year: str
    result: str
    round: str
    with_: str
    title: str
    note: str


@dataclass
class Game:
    seed: Seed
    headers: dict
    moves: list[chess.Move]
    book: int = 0
    analysis: list[list[tuple[str, int]]] = field(default_factory=list)
    keys: list[bool] = field(default_factory=list)


def read_seeds(lines: Iterable[str]) -> list[Seed]:
    rows = [l for l in lines if l.strip() and not l.startswith("#")]
    seeds = []
    for row in csv.DictReader(rows, delimiter="\t", quoting=csv.QUOTE_NONE):
        seeds.append(Seed(**{("with_" if k == "with" else k): (v or "").strip() for k, v in row.items()}))
    ids = [s.id for s in seeds]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        raise ValueError(f"duplicate ids: {sorted(dup)}")
    return seeds


def _fold(text: str) -> str:
    """Lowercase without accents or punctuation, for name matching."""
    text = unicodedata.normalize("NFKD", text)
    return re.sub(r"[^a-z0-9 ]", "", "".join(c for c in text if not unicodedata.combining(c)).lower())


def matches(seed: Seed, headers: dict) -> bool:
    if _fold(seed.white) not in _fold(headers.get("White", "")):
        return False
    if _fold(seed.black) not in _fold(headers.get("Black", "")):
        return False
    if not headers.get("Date", "").startswith(seed.year):
        return False
    if headers.get("Result") != seed.result:
        return False
    if seed.round:
        rnd = headers.get("Round", "")
        if rnd != seed.round and not rnd.startswith(seed.round + "."):
            return False
    return True


def find(seed: Seed, pgn_text: str) -> chess.pgn.Game:
    """The one game of `pgn_text` the seed names (a game found twice, with
    the same moves, counts once); ValueError otherwise."""
    offsets = []
    stream = io.StringIO(pgn_text)
    while True:
        offset = stream.tell()
        headers = chess.pgn.read_headers(stream)
        if headers is None:
            break
        if matches(seed, headers):
            offsets.append(offset)
    found = {}
    for offset in offsets:
        stream.seek(offset)
        game = chess.pgn.read_game(stream)
        if game.errors:
            raise ValueError(f"{seed.id}: {game.errors[0]}")
        san = game.board().variation_san(list(game.mainline_moves()))
        if seed.with_ and seed.with_ not in san:
            continue
        found.setdefault(san, game)
    if len(found) != 1:
        raise ValueError(f"{seed.id}: {len(found)} games match in {seed.source}")
    return next(iter(found.values()))


# The source's spellings shown in English
SPELLINGS = {"Jussupow": "Yusupov"}
# names shown in full, as the source writes them: the Polgar sisters
FULL_NAMES = {"Polgar, Judit": "Judit Polgar", "Polgar,Ju": "Judit Polgar", "Polgar, Sofia": "Sofia Polgar"}


def display_name(name: str) -> str:
    """The name shown: the surname ('Morphy, Paul ' -> 'Morphy'), else the
    name without a note ('Deep Blue (Computer)', 'Comp Deep Blue' ->
    'Deep Blue')."""
    name = " ".join(re.sub(r"\([^)]*\)", "", name).split())
    name = re.sub(r"^Comp ", "", name)
    if name in FULL_NAMES:
        return FULL_NAMES[name]
    if "," in name:
        name = name.split(",", 1)[0].strip()
    return SPELLINGS.get(name, name)


def book_plies(moves: list[chess.Move], opening_keys: set[str]) -> int:
    """The plies through the last named position (pkopeningnames' key)."""
    from .openings import position_key
    board = chess.Board()
    book = 0
    for i, move in enumerate(moves, 1):
        board.push(move)
        if position_key(board) in opening_keys:
            book = i
    return book


def score_cp(score: chess.engine.PovScore, turn: chess.Color) -> int:
    s = score.pov(turn)
    mate = s.mate()
    if mate is not None:
        return MATE - 10 * mate if mate > 0 else -MATE - 10 * mate
    return s.score()


def is_key(board: chess.Board, move: chess.Move, entry: list[tuple[str, int]],
           last: chess.Move | None) -> bool:
    """Whether the master's `move` at `board` is a key moment (see KEY_*):
    not an answer to a check, nor a recapture."""
    if len(entry) < 2 or board.is_check():
        return False
    scores = dict(entry)
    played = scores.get(move.uci())
    if played is None or win(played) < win(entry[0][1]) - KEY_NEAR_BEST:
        return False
    other = max(cp for uci, cp in entry if uci != move.uci())
    if win(played) - win(other) < KEY_GAP:
        return False
    if last is not None and move.to_square == last.to_square and board.is_capture(move):
        return False
    return True


Analyser = Callable[[chess.Board, chess.Move], list[tuple[str, int]]]


def analyse_game(game: Game, analyser: Analyser) -> None:
    """Scores the plies after the book (the opening is played, not guessed)."""
    board = chess.Board()
    last = None
    game.analysis, game.keys = [], []
    for i, move in enumerate(game.moves, 1):
        entry = analyser(board, move) if i > game.book else []
        game.analysis.append(entry)
        game.keys.append(bool(entry) and is_key(board, move, entry, last))
        board.push(move)
        last = move


def stockfish_analyser(engine_path: str, depth: int, cache_dir: Path,
                       threads: int = 1) -> tuple[Analyser, Callable[[], None]]:
    """An analyser over a Stockfish binary, its answers cached by position,
    depth and move in `cache_dir` (with several threads a new run may score
    differently: the cache keeps the committed data stable)."""
    import chess.engine
    engine = chess.engine.SimpleEngine.popen_uci(engine_path)
    engine.configure({"Threads": threads, "Hash": 64 * threads})
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_file = cache_dir / f"analysis-d{depth}.json"
    cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}

    def analyse(board: chess.Board, move: chess.Move) -> list[tuple[str, int]]:
        key = hashlib.sha1(f"{board.fen()} {move.uci()} {depth}".encode()).hexdigest()
        if key not in cache:
            limit = chess.engine.Limit(depth=depth)
            infos = engine.analyse(board, limit, multipv=3)
            entry = [(i["pv"][0].uci(), score_cp(i["score"], board.turn)) for i in infos if i.get("pv")]
            if move.uci() not in dict(entry):
                info = engine.analyse(board, limit, root_moves=[move])
                entry.append((move.uci(), score_cp(info["score"], board.turn)))
            cache[key] = entry
        return [tuple(e) for e in cache[key]]

    def save() -> None:
        tmp = cache_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(cache))
        tmp.replace(cache_file)

    def close() -> None:
        save()
        engine.quit()

    analyse.save = save  # (the CLI saves after each game: a long run can stop)
    return analyse, close


def fetch_source(name: str, cache_dir: Path) -> str:
    """The PGN text of PGN Mentor's player file `name` (cached)."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    path = cache_dir / f"{name}.zip"
    if not path.exists():
        # the site refuses Python's default User-Agent; say who we are, and
        # leave a pause between downloads
        request = urllib.request.Request(PGNMENTOR_URL.format(name), headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=60) as r:
            path.write_bytes(r.read())
        time.sleep(2)
    with zipfile.ZipFile(path) as z:
        member = next(n for n in z.namelist() if n.lower().endswith(".pgn"))
        return z.read(member).decode("latin-1")


def load(seeds: list[Seed], source: Callable[[str], str], opening_keys: set[str]) -> list[Game]:
    texts: dict[str, str] = {}
    games = []
    for seed in seeds:
        if seed.source not in texts:
            texts[seed.source] = source(seed.source)
        pgn = find(seed, texts[seed.source])
        moves = list(pgn.mainline_moves())
        games.append(Game(seed, dict(pgn.headers), moves, book_plies(moves, opening_keys)))
    return games


def _clean(text: str) -> str:
    return " ".join(text.replace("\t", " ").split()).strip("? ")


def write(games: list[Game], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as f:
        f.write(HEADER)
        for g in games:
            h, s = g.headers, g.seed
            analysis = " ".join(("!" if key else "") + (",".join(f"{u}:{cp}" for u, cp in entry) or "-")
                                for entry, key in zip(g.analysis, g.keys))
            fields = [s.id, s.title, display_name(h.get("White", "")), display_name(h.get("Black", "")),
                      _clean(h.get("Event", "")), _clean(h.get("Site", "")), s.year,
                      _clean(h.get("Round", "")), s.result, s.note, str(g.book),
                      " ".join(m.uci() for m in g.moves), analysis]
            f.write("\t".join(_clean(x) if i != 12 else x for i, x in enumerate(fields)) + "\n")


def opening_keys(path: Path) -> set[str]:
    keys = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            keys.add(line.split("\t", 1)[0])
    return keys
