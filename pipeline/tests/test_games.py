import chess
import pytest

from paperknight_pipeline import games

SEEDS = (
    "# comment\n"
    "id\tsource\twhite\tblack\tyear\tresult\tround\twith\ttitle\tnote\n"
    "opera\tMorphy\tMorphy\tIsouard\t1858\t1-0\t\t\tThe Opera Game\tA miniature.\n"
    "second\tMorphy\tMorphy\tAnderssen\t1858\t1-0\t\tQxf7\tA second\tAnother.\n"
)

# a game twice (the same moves), two games between the same players
PGN = """[Event "Paris"]
[Date "1858.??.??"]
[Round "?"]
[White "Morphy, Paul "]
[Black "Duke Karl Count Isouard"]
[Result "1-0"]

1.e4 e5 2.Nf3 d6 3.d4 Bg4 4.dxe5 Bxf3 5.Qxf3 dxe5 6.Bc4 Nf6 7.Qb3 Qe7 8.Nc3 c6
9.Bg5 b5 10.Nxb5 cxb5 11.Bxb5+ Nbd7 12.O-O-O Rd8 13.Rxd7 Rxd7 14.Rd1 Qe6
15.Bxd7+ Nxd7 16.Qb8+ Nxb8 17.Rd8# 1-0

[Event "Paris (again)"]
[Date "1858.??.??"]
[White "Morphy, Paul"]
[Black "Duke Karl Count Isouard"]
[Result "1-0"]

1.e4 e5 2.Nf3 d6 3.d4 Bg4 4.dxe5 Bxf3 5.Qxf3 dxe5 6.Bc4 Nf6 7.Qb3 Qe7 8.Nc3 c6
9.Bg5 b5 10.Nxb5 cxb5 11.Bxb5+ Nbd7 12.O-O-O Rd8 13.Rxd7 Rxd7 14.Rd1 Qe6
15.Bxd7+ Nxd7 16.Qb8+ Nxb8 17.Rd8# 1-0

[Event "Paris m"]
[Date "1858.??.??"]
[White "Morphy, Paul"]
[Black "Anderssen, Adolf"]
[Result "1-0"]

1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6 4.Qxf7# 1-0

[Event "Paris m"]
[Date "1858.??.??"]
[White "Morphy, Paul"]
[Black "Anderssen, Adolf"]
[Result "1-0"]

1.e4 e5 2.Bc4 Bc5 3.Qh5 Nf6 4.Qxf7# 1-0
"""


def seeds():
    return games.read_seeds(SEEDS.splitlines())


def test_seeds_read_and_duplicate_ids_refused():
    s = seeds()
    assert [x.id for x in s] == ["opera", "second"]
    assert s[1].with_ == "Qxf7" and s[0].round == ""
    with pytest.raises(ValueError, match="duplicate"):
        games.read_seeds((SEEDS + SEEDS.splitlines()[-1] + "\n").splitlines())


def test_find_one_game_the_same_moves_twice_count_once():
    game = games.find(seeds()[0], PGN)
    assert game.headers["Event"] == "Paris"
    assert len(list(game.mainline_moves())) == 33


def test_find_several_or_none_refused():
    second = seeds()[1]
    with pytest.raises(ValueError, match="2 games match"):
        games.find(second, PGN)  # both games have Qxf7#
    second.with_ = "2. Bc4 Nc6"
    assert games.find(second, PGN).headers["Black"] == "Anderssen, Adolf"
    second.year = "1859"
    with pytest.raises(ValueError, match="0 games match"):
        games.find(second, PGN)


def test_names_and_book():
    assert games.display_name("Morphy, Paul ") == "Morphy"
    assert games.display_name("Deep Blue (Computer)") == "Deep Blue"
    assert games.display_name("Comp Deep Blue") == "Deep Blue"
    assert games.display_name("Jussupow, Artur") == "Yusupov"
    assert games.display_name("Duke Karl Count Isouard") == "Duke Karl Count Isouard"
    moves = [chess.Move.from_uci(m) for m in "e2e4 e7e5 g1f3 d7d6 d2d4".split()]
    from paperknight_pipeline.openings import position_key
    b = chess.Board()
    keys = set()
    for m in moves[:4]:
        b.push(m)
    keys.add(position_key(b))  # named after 2...d6
    assert games.book_plies(moves, keys) == 4
    assert games.book_plies(moves, set()) == 0


def test_mate_scores_and_winning_chances():
    assert games.win(0) == 50
    assert games.win(10000) > 99 and games.win(-10000) < 1
    assert round(games.win(300)) == 75


def test_key_moments():
    # 16. Qb8+ of the Opera Game: mates, the next best only wins
    board = games.find(seeds()[0], PGN).board()
    for move in list(games.find(seeds()[0], PGN).mainline_moves())[:30]:
        board.push(move)
    move = chess.Move.from_uci("b3b8")
    assert games.is_key(board, move, [("b3b8", 9980), ("b3b7", 366), ("b3c3", 355)], None)
    # another move as good: no key moment
    assert not games.is_key(board, move, [("b3b8", 9980), ("b3b7", 9970)], None)
    # the master's move clearly not the best
    assert not games.is_key(board, move, [("b3b7", 900), ("b3c3", 100), ("b3b8", 300)], None)
    # a single move listed (forced): no key moment
    assert not games.is_key(board, move, [("b3b8", 9980)], None)


def test_no_key_moment_in_check_or_for_a_recapture():
    check = chess.Board("4k3/8/8/8/8/8/4r3/4K2R w K - 0 1")  # the rook checks
    move = chess.Move.from_uci("e1e2")
    assert not games.is_key(check, move, [("e1e2", 500), ("e1f1", -500)], None)
    # 1. e4 d5 2. exd5 Qxd5: recapturing the queen's pawn on d5
    board = chess.Board()
    for m in "e2e4 d7d5 e4d5".split():
        board.push_uci(m)
    last = chess.Move.from_uci("e4d5")
    recapture = chess.Move.from_uci("d8d5")
    assert not games.is_key(board, recapture, [("d8d5", 0), ("g8f6", -300)], last)
    assert games.is_key(board, recapture, [("d8d5", 0), ("g8f6", -300)], None)


def test_written_line(tmp_path):
    game = games.Game(seeds()[0], {"White": "Morphy, Paul ", "Black": "Duke Karl Count Isouard",
                                   "Event": "Paris\tit", "Site": "?", "Round": "?"},
                      [chess.Move.from_uci("e2e4"), chess.Move.from_uci("e7e5")], book=1)
    calls = []

    def analyser(board, move):
        calls.append(board.fen())
        if move.uci() == "e2e4":
            return [("e2e4", 50), ("d2d4", 37)]
        return [("c7c5", -30), ("e7e6", -35), ("e7e5", -44)]

    games.analyse_game(game, analyser)
    assert len(calls) == 1, "the book ply is not analysed"
    assert game.analysis[0] == [] and game.keys == [False, False]
    game.book = 0
    games.analyse_game(game, analyser)
    assert len(calls) == 3 and game.keys == [False, False]
    game.keys = [False, True]
    out = tmp_path / "games.tsv"
    games.write([game], out)
    game.analysis[0] = []
    games.write([game], tmp_path / "book.tsv")
    assert (tmp_path / "book.tsv").read_text().splitlines()[1].split("\t")[12].startswith("- !c7c5")
    lines = out.read_text().splitlines()
    assert lines[0].startswith("#")
    f = lines[1].split("\t")
    assert len(f) == 13
    assert f[:5] == ["opera", "The Opera Game", "Morphy", "Duke Karl Count Isouard", "Paris it"]
    assert f[5] == "" and f[7] == ""  # unknown site and round
    assert f[8:12] == ["1-0", "A miniature.", "0", "e2e4 e7e5"]
    assert f[12] == "e2e4:50,d2d4:37 !c7c5:-30,e7e6:-35,e7e5:-44"
