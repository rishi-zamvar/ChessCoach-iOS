#!/usr/bin/env python3
"""Validate the annotated PGN repertoires in ChessCoachKit/Resources/repertoires.

Checks: parses, all moves legal, headers present, %cal/%csl syntax, only known
[%...] commands, every main-line user move commented, and a crude soundness pass:
  - a user move that drops material by a one-step static exchange is flagged
  - a line whose leaf leaves the user down material is flagged
Both are skipped inside [%trap] subtrees and for lines whose comments say
"gambit"/"sacrifice"/"trick" (deliberate material investment).
ponytail: one-step SEE (min attacker vs piece), not a full exchange sequence;
use a real SEE / engine eval if false positives/negatives start to bite.

Usage: python scripts/validate_repertoires.py   (needs python-chess)
Exit code 1 on any error or flag.
"""
import io
import re
import sys
from pathlib import Path

import chess
import chess.pgn

DIR = Path(__file__).resolve().parent.parent / "Packages/ChessCoachKit/Sources/ChessCoachKit/Resources/repertoires"
STYLES = ["attacker", "tactician", "positional", "allRounder"]
SIDES = ["white", "black-e4", "black-d4"]
HEADERS = ["Event", "Side", "Style", "Name", "Summary", "Result"]
VAL = {chess.PAWN: 1, chess.KNIGHT: 3, chess.BISHOP: 3, chess.ROOK: 5, chess.QUEEN: 9, chess.KING: 100}
CMD = re.compile(r"\[%(\w+)([^\]]*)\]")
ALLOW = re.compile(r"gambit|sacrific|trick", re.I)


def material(board, color):
    return sum(VAL[p.piece_type] for p in board.piece_map().values() if p.color == color and p.piece_type != chess.KING)


def drops_material(board, move):
    """One-step static exchange on the destination square after `move`."""
    us = board.turn
    captured = board.piece_at(move.to_square)
    gain = VAL[captured.piece_type] if captured else (1 if board.is_en_passant(move) else 0)
    b = board.copy()
    b.push(move)
    if b.is_checkmate():
        return False
    piece = b.piece_at(move.to_square)
    if piece is None or board.is_castling(move):
        return False
    attackers = b.attackers(not us, move.to_square)
    if not attackers:
        return False
    # pawn/piece tension: we also hit an equal-or-bigger attacker, so a trade is on, not a hang
    if any(s in b.attacks(move.to_square) and VAL[b.piece_at(s).piece_type] >= VAL[piece.piece_type] for s in attackers):
        return False
    defended = bool(b.attackers(us, move.to_square))
    min_att = min(VAL[b.piece_at(s).piece_type] for s in attackers)
    if not defended:
        loss = VAL[piece.piece_type]
    else:
        loss = 0 if min_att >= 100 else max(0, VAL[piece.piece_type] - min_att)
    return gain - loss < 0


def hanging_after(board, move):
    """Squares of the mover's pieces (other than the moved one) left en prise after `move`."""
    us = board.turn
    b = board.copy()
    b.push(move)
    if b.is_checkmate():
        return []
    out = []
    for sq, p in b.piece_map().items():
        if p.color != us or p.piece_type == chess.KING or sq == move.to_square:
            continue
        att = b.attackers(not us, sq)
        if not att:
            continue
        min_att = min(VAL[b.piece_at(s).piece_type] for s in att)
        if any(s in b.attacks(sq) and VAL[b.piece_at(s).piece_type] >= VAL[p.piece_type] for s in att):
            continue
        if not b.attackers(us, sq) and min_att < 100 or min_att < VAL[p.piece_type]:
            out.append(chess.square_name(sq))
    return out


def check_commands(comment, where, errors):
    for name, arg in CMD.findall(comment):
        arg = arg.strip()
        if name == "cal":
            for t in arg.split(","):
                if not re.fullmatch(r"[GRBY][a-h][1-8][a-h][1-8]", t) or t[1:3] == t[3:5]:
                    errors.append(f"{where}: bad %cal token '{t}'")
        elif name == "csl":
            for t in arg.split(","):
                if not re.fullmatch(r"[GRBY][a-h][1-8]", t):
                    errors.append(f"{where}: bad %csl token '{t}'")
        elif name == "dev":
            if arg:
                errors.append(f"{where}: %dev takes no argument")
        elif name == "trap":
            if not arg:
                errors.append(f"{where}: %trap needs a name")
        else:
            errors.append(f"{where}: unknown command %{name}")
    stripped = CMD.sub("", comment).strip()
    if comment and not stripped:
        errors.append(f"{where}: comment has commands but no idea text")


def label(node):
    b = node.parent.board()
    n = b.fullmove_number
    return f"{n}{'.' if b.turn == chess.WHITE else '...'}{b.san(node.move)}"


def validate(path):
    errors, flags, warns = [], [], []
    text = path.read_text()
    game = chess.pgn.read_game(io.StringIO(text))
    if game is None:
        return {"errors": [f"{path.name}: no game"], "flags": [], "warns": []}
    if text.count("[Event ") > 1:
        errors.append("more than one game in file")
    for e in game.errors:
        errors.append(f"parse/illegal: {e}")
    for h in HEADERS:
        if not game.headers.get(h) or game.headers.get(h) == "?":
            errors.append(f"missing header {h}")
    side = game.headers.get("Side")
    if side not in ("white", "black"):
        errors.append(f"bad Side header {side!r}")
    user = chess.WHITE if side == "white" else chess.BLACK
    stem_side = "white" if path.stem.endswith("-white") else "black"
    if side != stem_side:
        errors.append(f"Side header {side} does not match filename")
    if game.headers.get("Style") != path.stem.split("-")[0]:
        errors.append("Style header does not match filename")

    stats = {"nodes": 0, "branches": 0, "traps": 0, "devs": 0, "leaves": 0, "main_plies": 0}

    def walk(node, in_trap, allowed, mainline):
        board = node.board()
        if len(node.variations) > 1:
            stats["branches"] += 1
        if not node.variations:
            stats["leaves"] += 1
            diff = material(board, user) - material(board, not user)
            mated_user = board.is_checkmate() and board.turn == user
            if (diff < 0 or mated_user) and not in_trap and not allowed:
                flags.append(f"line ends with user down material ({diff:+d}) at {label(node)}")
            return
        for child in node.variations:
            stats["nodes"] += 1
            c = child.comment
            where = label(child)
            check_commands(c, where, errors)
            trap = in_trap or "[%trap" in c
            stats["traps"] += "[%trap" in c
            stats["devs"] += "[%dev" in c
            ok = allowed or bool(ALLOW.search(c))
            is_main = mainline and child is node.variations[0]
            if board.turn == user:
                if is_main and not CMD.sub("", c).strip():
                    errors.append(f"main-line user move without idea comment: {where}")
                if child is not node.variations[0] and "[%trap" not in c:
                    errors.append(f"user alternative move must be a [%trap] line: {where}")
                if not trap and not ok and drops_material(board, child.move):
                    flags.append(f"user move drops material (static exchange): {where}")
                if not trap and not ok:
                    # at a leaf nobody shows the reply, so a loose piece is a real hole; mid-line
                    # the next opponent move is shown, so just warn for a human to eyeball.
                    for sq in hanging_after(board, child.move):
                        (flags if not child.variations else warns).append(f"user move leaves {sq} en prise: {where}")
            else:
                if child is not node.variations[0] and "[%dev" not in c and "[%trap" not in c:
                    errors.append(f"opponent alternative without [%dev]/[%trap]: {where}")
            if is_main:
                stats["main_plies"] += 1
            walk(child, trap, ok, is_main)

    walk(game, False, False, True)
    return {"name": game.headers.get("Name", "?"), "errors": errors, "flags": flags, "warns": warns, **stats}


def main():
    expected = [f"{s}-{side}.pgn" for s in STYLES for side in SIDES]
    missing = [f for f in expected if not (DIR / f).exists()]
    extra = sorted(p.name for p in DIR.glob("*.pgn") if p.name not in expected)
    bad = bool(missing)
    print(f"{'file':<26}{'nodes':>6}{'main':>6}{'branch':>7}{'leaves':>7}{'dev':>5}{'traps':>6}  name")
    for f in expected:
        if f in missing:
            continue
        r = validate(DIR / f)
        print(f"{f:<26}{r.get('nodes',0):>6}{r.get('main_plies',0):>6}{r.get('branches',0):>7}"
              f"{r.get('leaves',0):>7}{r.get('devs',0):>5}{r.get('traps',0):>6}  {r.get('name')}")
        for e in r["errors"]:
            print(f"    ERROR {e}")
        for fl in r["flags"]:
            print(f"    FLAG  {fl}")
        for w in r.get("warns", []):
            print(f"    warn  {w}")
        bad |= bool(r["errors"] or r["flags"])
    for f in missing:
        print(f"MISSING {f}")
    for f in extra:
        print(f"UNEXPECTED {f}")
    print("FAIL" if bad else "OK: all repertoires valid")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
