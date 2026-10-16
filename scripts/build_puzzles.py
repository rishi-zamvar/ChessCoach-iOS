#!/usr/bin/env python3
"""Build ChessCoach/Resources/puzzles.sqlite from the Lichess puzzle DB (CC0).

Usage: python3 scripts/build_puzzles.py lichess_db_puzzle.csv.zst [out.sqlite] [target]
puzzle_theme carries a denormalised rating so (theme, rating) is one index.
Streams `zstd -dc` -> csv; filters for quality, then stratifies by
(primary theme x 100-point rating bucket) with a per-cell cap sized to ~target rows.
"""
import csv, io, os, random, sqlite3, subprocess, sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = 60_000
RESERVOIR = 3_000  # per-cell reservoir; final cap is chosen <= this after the pass
SEED = 20261016

MATE_N = ["mateIn1", "mateIn2", "mateIn3", "mateIn4", "mateIn5"]
ADVANCED = ["attraction", "clearance", "deflection", "discoveredCheck", "defensiveMove",
            "interference", "intermezzo", "quietMove", "xRayAttack", "zugzwang",
            "capturingDefender", "doubleCheck", "trappedPiece", "sacrifice"]
BASIC = ["fork", "pin", "skewer", "discoveredAttack", "hangingPiece", "advancedPawn",
         "attackingF2F7", "exposedKing", "kingsideAttack", "queensideAttack", "promotion",
         "underPromotion", "enPassant", "castling"]
ENDGAMES = ["pawnEndgame", "rookEndgame", "bishopEndgame", "knightEndgame",
            "queenEndgame", "queenRookEndgame"]
# Length/origin tags stay in puzzle.themes but are not indexed in puzzle_theme (size budget).
UNINDEXED = {"oneMove", "short", "long", "veryLong", "master", "masterVsMaster", "superGM"}
REST = ["mate", "crushing", "advantage", "equality", "endgame", "middlegame", "opening"]


def primary_theme(themes):
    named = sorted(t for t in themes if t.endswith("Mate"))
    if named:
        return named[0]
    for group in (MATE_N, ADVANCED, BASIC, ENDGAMES, REST):
        for t in group:
            if t in themes:
                return t
    return "other"


def keep(r):
    try:
        rating, rd, pop, plays = int(r[3]), int(r[4]), int(r[5]), int(r[6])
    except ValueError:
        return False
    return rd <= 80 and pop >= 85 and plays >= 200 and 400 <= rating <= 2000


def choose_cap(sizes, target):
    lo, hi = 1, RESERVOIR
    while lo < hi:  # largest cap with total <= target
        mid = (lo + hi + 1) // 2
        if sum(min(n, mid) for n in sizes) <= target:
            lo = mid
        else:
            hi = mid - 1
    return lo


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "ChessCoach/Resources/puzzles.sqlite")
    target = int(sys.argv[3]) if len(sys.argv) > 3 else TARGET
    rng = random.Random(SEED)
    cells, seen = {}, Counter()
    total = kept = 0
    proc = subprocess.Popen(["zstd", "-dc", src], stdout=subprocess.PIPE)
    reader = csv.reader(io.TextIOWrapper(proc.stdout, encoding="utf-8", newline=""))
    next(reader)  # header
    for r in reader:
        total += 1
        if not keep(r):
            continue
        kept += 1
        themes = r[7].split()
        key = (primary_theme(themes), int(r[3]) // 100)
        seen[key] += 1
        row = (r[0], r[1], r[2], int(r[3]), int(r[4]), int(r[5]), int(r[6]),
               " ".join(themes), key[0],
               r[9].split()[-1] if r[9] else None)  # most specific opening tag only (size budget)
        cell = cells.setdefault(key, [])
        if len(cell) < RESERVOIR:
            cell.append(row)
        else:  # Algorithm R
            j = rng.randrange(seen[key])
            if j < RESERVOIR:
                cell[j] = row
    if proc.wait() != 0:
        sys.exit("zstd failed")

    cap = choose_cap([len(c) for c in cells.values()], target)
    chosen = []
    for key in sorted(cells):
        c = cells[key]
        chosen.extend(c if len(c) <= cap else rng.sample(c, cap))
    chosen.sort(key=lambda row: row[0])

    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.executescript("""
      CREATE TABLE puzzle(id TEXT PRIMARY KEY, fen TEXT NOT NULL, moves TEXT NOT NULL,
        rating INT NOT NULL, rd INT NOT NULL, popularity INT NOT NULL, plays INT NOT NULL,
        themes TEXT NOT NULL, primaryTheme TEXT NOT NULL, opening TEXT) WITHOUT ROWID;
      CREATE TABLE puzzle_theme(puzzleId TEXT NOT NULL, theme TEXT NOT NULL, rating INT NOT NULL,
        PRIMARY KEY (theme, rating, puzzleId)) WITHOUT ROWID;  -- the PK is the (theme, rating) index
    """)
    db.executemany("INSERT INTO puzzle VALUES (?,?,?,?,?,?,?,?,?,?)", chosen)
    db.executemany("INSERT INTO puzzle_theme VALUES (?,?,?)",
                   ((row[0], t, row[3]) for row in chosen for t in row[7].split() if t not in UNINDEXED))
    db.executescript("""
      CREATE INDEX puzzle_rating ON puzzle(rating);
    """)
    db.commit()
    db.execute("VACUUM")
    db.close()

    print(f"rows read {total}, passed filter {kept}, cells {len(cells)}, cap {cap}, bundled {len(chosen)}")
    for theme, n in Counter(row[8] for row in chosen).most_common():
        print(f"  {theme:20s} {n}")
    print(f"{out}: {os.path.getsize(out) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
