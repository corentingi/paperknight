"""Command line: `python -m paperknight_pipeline <command> ...`."""
from __future__ import annotations

import argparse
import os
import sys
import urllib.error
from datetime import date
from pathlib import Path

from . import puzzles, sources, studies

REPO = Path(__file__).resolve().parents[2]
DOWNLOADS = REPO / "build" / "downloads"
PACKS = REPO / "build" / "packs"


def cmd_puzzles(args: argparse.Namespace) -> int:
    if args.input:
        src = Path(args.input)
        label = f"{src.name} (local file)"
    else:
        print(f"downloading {sources.LICHESS_PUZZLES_URL} (cached in {DOWNLOADS}) ...", file=sys.stderr)
        try:
            src = sources.download(sources.LICHESS_PUZZLES_URL, DOWNLOADS, force=args.refresh)
        except (urllib.error.URLError, OSError) as e:
            print(f"download failed: {e}", file=sys.stderr)
            return 1
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


def cmd_study(args: argparse.Namespace) -> int:
    study_id = studies.parse_study_id(args.study)
    if args.input:
        pgn = Path(args.input).read_text(encoding="utf-8")
    else:
        token = os.environ.get(args.token_env) if args.token_env else None
        print(f"downloading study {study_id} ...", file=sys.stderr)
        try:
            pgn = studies.download_study(study_id, token)
        except urllib.error.HTTPError as e:
            hint = (f" (private study? put a token with study:read in ${args.token_env})"
                    if e.code in (401, 403, 404) else "")
            print(f"download failed: HTTP {e.code}{hint}", file=sys.stderr)
            return 1
        except (urllib.error.URLError, TimeoutError, OSError) as e:  # offline, DNS, timeout
            print(f"download failed: {getattr(e, 'reason', e)}", file=sys.stderr)
            return 1
    report = studies.validate(pgn)
    if report.chapters == 0:
        print("no chapters found (private study? set a token with --token-env)", file=sys.stderr)
        return 1
    path = studies.save(pgn, Path(args.output_dir), report.name or study_id, study_id)
    print(f"{path}: {report.chapters} chapters ({report.gamebook_chapters} interactive), {report.moves} moves")
    for problem in report.problems:
        print(f"  warning: {problem}", file=sys.stderr)
    return 0


def positive_int(text: str) -> int:
    value = int(text)
    if value < 1:
        raise argparse.ArgumentTypeError(f"must be at least 1, got {value}")
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="paperknight_pipeline", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("puzzles", help="build puzzles.sqlite from the Lichess puzzle database")
    p.add_argument("--input", help="local CSV or CSV.zst (default: download the Lichess dump)")
    p.add_argument("--output", default=str(PACKS / "puzzles.sqlite"))
    defaults = puzzles.Selection()
    p.add_argument("--refresh", action="store_true",
                   help="download the Lichess dump again (it is cached; Lichess updates it monthly)")
    p.add_argument("--per-band", type=positive_int, default=defaults.per_band, help="max puzzles per rating band")
    p.add_argument("--band-width", type=positive_int, default=defaults.band_width)
    p.add_argument("--min-popularity", type=int, default=defaults.min_popularity)
    p.add_argument("--min-plays", type=int, default=defaults.min_plays)
    p.add_argument("--max-rating-dev", type=int, default=defaults.max_rating_dev)
    p.set_defaults(func=cmd_puzzles)

    p = sub.add_parser("study", help="download a Lichess study as PGN and validate it")
    p.add_argument("study", help="study id (8 characters) or lichess.org/study/... URL")
    p.add_argument("--output-dir", default=str(REPO / "build" / "studies"))
    p.add_argument("--token-env", default="LICHESS_TOKEN",
                   help="environment variable holding a Lichess token (needed for private studies)")
    p.add_argument("--input", help="validate a local PGN instead of downloading (tests)")
    p.set_defaults(func=cmd_study)

    args = parser.parse_args(argv)
    return args.func(args)
