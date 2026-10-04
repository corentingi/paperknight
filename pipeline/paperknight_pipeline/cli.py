"""Command line: `python -m paperknight_pipeline <command> ...`."""
from __future__ import annotations

import argparse
import sys
from datetime import date
from pathlib import Path

from . import puzzles, sources

REPO = Path(__file__).resolve().parents[2]
DOWNLOADS = REPO / "build" / "downloads"
PACKS = REPO / "build" / "packs"


def cmd_puzzles(args: argparse.Namespace) -> int:
    if args.input:
        src = Path(args.input)
        label = f"{src.name} (local file)"
    else:
        print(f"downloading {sources.LICHESS_PUZZLES_URL} (cached in {DOWNLOADS}) ...", file=sys.stderr)
        src = sources.download(sources.LICHESS_PUZZLES_URL, DOWNLOADS)
        label = f"{sources.LICHESS_PUZZLES_URL} (downloaded {date.fromtimestamp(src.stat().st_mtime)})"
    sel = puzzles.Selection(
        per_band=args.per_band,
        band_width=args.band_width,
        min_popularity=args.min_popularity,
        min_plays=args.min_plays,
        max_rating_dev=args.max_rating_dev,
    )
    with sources.open_text(src) as lines:
        stats = puzzles.build_pack(lines, Path(args.output), sel, label)
    if stats["written"]:
        print(f"{args.output}: {stats['written']} puzzles ({stats['invalid']} invalid candidates dropped)")
    else:
        print(f"no puzzles selected; {args.output} not written", file=sys.stderr)
    return 0 if stats["written"] else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="paperknight_pipeline", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("puzzles", help="build puzzles.sqlite from the Lichess puzzle database")
    p.add_argument("--input", help="local CSV or CSV.zst (default: download the Lichess dump)")
    p.add_argument("--output", default=str(PACKS / "puzzles.sqlite"))
    defaults = puzzles.Selection()
    p.add_argument("--per-band", type=int, default=defaults.per_band, help="max puzzles per rating band")
    p.add_argument("--band-width", type=int, default=defaults.band_width)
    p.add_argument("--min-popularity", type=int, default=defaults.min_popularity)
    p.add_argument("--min-plays", type=int, default=defaults.min_plays)
    p.add_argument("--max-rating-dev", type=int, default=defaults.max_rating_dev)
    p.set_defaults(func=cmd_puzzles)

    args = parser.parse_args(argv)
    return args.func(args)
