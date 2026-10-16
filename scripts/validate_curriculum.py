#!/usr/bin/env python3
"""Validate Resources/curriculum.json with python-chess.

Usage: python scripts/validate_curriculum.py [path/to/curriculum.json]
Exits non-zero on the first batch of errors. Needs `pip install chess`.
Stockfish (optional, on PATH) is used to confirm faded first moves are best.
"""
import json
import shutil
import sys
from functools import lru_cache
from pathlib import Path

import chess
import chess.engine

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ROOT / "Packages/ChessCoachKit/Sources/ChessCoachKit/Resources/curriculum.json"

# Lichess puzzle theme tags (research 01 §3.2).
LICHESS_THEMES = set("""
opening middlegame endgame rookEndgame bishopEndgame pawnEndgame knightEndgame queenEndgame queenRookEndgame
advancedPawn attackingF2F7 capturingDefender discoveredAttack doubleCheck exposedKing fork hangingPiece
kingsideAttack pin queensideAttack sacrifice skewer trappedPiece attraction clearance collinearMove
discoveredCheck defensiveMove deflection interference intermezzo quietMove xRayAttack zugzwang
mate mateIn1 mateIn2 mateIn3 mateIn4 mateIn5 anastasiaMate arabianMate backRankMate balestraMate
blindSwineMate bodenMate cornerMate doubleBishopMate dovetailMate epauletteMate hookMate killBoxMate
pillsburysMate morphysMate operaMate swallowstailMate triangleMate vukovicMate smotheredMate
castling enPassant promotion underPromotion equality advantage crushing oneMove short long veryLong
master masterVsMaster superGM
""".split())
KINDS = {"puzzles", "coordinates", "checksCaptures", "safeMove", "playout"}
GOALS = {"mate", "draw", "promote"}
COLORS = {"green", "red", "blue", "yellow"}
VALUE = {chess.PAWN: 1, chess.KNIGHT: 3, chess.BISHOP: 3, chess.ROOK: 5, chess.QUEEN: 9, chess.KING: 100}

errors = []


def err(lesson, msg):
    errors.append(f"[{lesson}] {msg}")


def board_for(lid, fen, where):
    try:
        b = chess.Board(fen)
    except ValueError as e:
        err(lid, f"{where}: bad FEN {fen!r}: {e}")
        return None
    if not b.is_valid():
        err(lid, f"{where}: illegal position {fen!r} ({b.status()!r})")
        return None
    return b


def play(lid, b, moves, where):
    for i, uci in enumerate(moves):
        try:
            m = chess.Move.from_uci(uci)
        except ValueError:
            err(lid, f"{where}: bad UCI {uci!r}")
            return False
        if m not in b.legal_moves:
            err(lid, f"{where}: move {i} {uci} illegal in {b.fen()}")
            return False
        b.push(m)
    return True


# --- theme-specific checks on the faded example's first user move ---------------------------

def is_fork(b, move):
    """cook.py-style: moved non-king piece attacks >=2 enemy pieces that are worth more or undefended."""
    after = b.copy()
    after.push(move)
    piece = after.piece_at(move.to_square)
    if piece is None or piece.piece_type == chess.KING:
        return False
    targets = 0
    for sq in after.attacks(move.to_square):
        t = after.piece_at(sq)
        if t and t.color != piece.color:
            undefended = not after.attackers(t.color, sq)
            if VALUE[t.piece_type] > VALUE[piece.piece_type] or undefended:
                targets += 1
    return targets >= 2


def has_pin(b, move):
    after = b.copy()
    after.push(move)
    them = after.turn
    return any(after.is_pinned(them, sq) for sq in chess.SquareSet(after.occupied_co[them]) if after.piece_type_at(sq) != chess.KING)


def is_skewer(b, move):
    """Check along a line with a non-pawn enemy piece behind the king on the same ray."""
    after = b.copy()
    after.push(move)
    if not after.is_check():
        return False
    king = after.king(after.turn)
    frm = move.to_square
    df = (chess.square_file(king) > chess.square_file(frm)) - (chess.square_file(king) < chess.square_file(frm))
    dr = (chess.square_rank(king) > chess.square_rank(frm)) - (chess.square_rank(king) < chess.square_rank(frm))
    f, r = chess.square_file(king) + df, chess.square_rank(king) + dr
    while 0 <= f < 8 and 0 <= r < 8:
        p = after.piece_at(chess.square(f, r))
        if p:
            return p.color == after.turn and p.piece_type in (chess.ROOK, chess.QUEEN, chess.BISHOP, chess.KNIGHT)
        f, r = f + df, r + dr
    return False


def is_discovered(b, move):
    """Moving piece uncovers a line piece's attack (check or on a queen/rook)."""
    after = b.copy()
    after.push(move)
    them = after.turn
    for sq in chess.SquareSet(after.occupied_co[them]):
        if VALUE[after.piece_type_at(sq)] < 5:
            continue
        for a in after.attackers(not them, sq):
            if a != move.to_square and a not in b.attackers(not them, sq):
                return True
    return False


def catches_pawn(b):
    """Side not to move has a king; side to move has one pawn. True if the king is in the square."""
    pawn_color = b.turn
    pawns = list(b.pieces(chess.PAWN, pawn_color))
    if len(pawns) != 1:
        return False
    p = pawns[0]
    promo = chess.square(chess.square_file(p), 7 if pawn_color == chess.WHITE else 0)
    start = 1 if pawn_color == chess.WHITE else 6
    steps = abs(chess.square_rank(promo) - chess.square_rank(p))
    if chess.square_rank(p) == start:
        steps -= 1
    return chess.square_distance(b.king(not pawn_color), promo) <= steps


@lru_cache(maxsize=None)
def kpk_win(board_fen, white_to_move, depth):
    """White (K+P) wins vs bare K within `depth` plies. Promotion to an uncapturable queen = win."""
    b = chess.Board(board_fen + (" w" if white_to_move else " b") + " - - 0 1")
    if depth == 0 or b.is_stalemate() or b.is_insufficient_material():
        return False
    if white_to_move:
        for m in b.legal_moves:
            if m.promotion and m.promotion != chess.QUEEN:
                continue
            b.push(m)
            if m.promotion:
                ok = not b.is_stalemate() and not any(b.is_capture(r) for r in b.legal_moves)
            else:
                ok = kpk_win(b.board_fen(), False, depth - 1)
            b.pop()
            if ok:
                return True
        return False
    for m in b.legal_moves:
        b.push(m)
        ok = kpk_win(b.board_fen(), True, depth - 1)
        b.pop()
        if not ok:
            return False
    return True


def kpk_winning_moves(b, depth=31):
    out = []
    for m in b.legal_moves:
        b.push(m)
        if kpk_win(b.board_fen(), False, depth - 1):
            out.append(m.uci())
        b.pop()
    return out


def material(b):
    return sum(VALUE[p.piece_type] * (1 if p.color == b.turn else -1) for p in b.piece_map().values() if p.piece_type != chess.KING)


def search(b, depth, alpha=-10**6, beta=10**6):
    """Tiny negamax: material + mate, captures-only quiescence. Fallback when Stockfish is absent."""
    if b.is_checkmate():
        return -10**5
    if b.is_stalemate() or b.is_insufficient_material():
        return 0
    stand = material(b)
    if depth <= 0:
        if stand >= beta:
            return stand
        alpha = max(alpha, stand)
        moves = [m for m in b.legal_moves if b.is_capture(m)]
    else:
        moves = list(b.legal_moves)
    best = stand if depth <= 0 else -10**6
    for m in moves:
        b.push(m)
        v = -search(b, depth - 1, -beta, -alpha)
        b.pop()
        best = max(best, v)
        alpha = max(alpha, v)
        if alpha >= beta:
            break
    return best


def best_first_moves(b, depth=4):
    scores = {}
    for m in b.legal_moves:
        b.push(m)
        scores[m.uci()] = -search(b, depth - 1)
        b.pop()
    top = max(scores.values())
    return [u for u, v in scores.items() if v == top], scores


# --- main ------------------------------------------------------------------------------------

def check_lesson(L, ids, engine):
    lid = L.get("id", "?")
    for key in ("id", "skill", "title", "band", "prerequisites", "idea", "keyPoints", "worked", "faded", "practice", "mastery"):
        if key not in L:
            err(lid, f"missing key {key}")
    lo, hi = L["band"]
    if not lo < hi:
        err(lid, f"bad band {L['band']}")
    for p in L["prerequisites"]:
        if p not in ids:
            err(lid, f"unknown prerequisite {p}")
    if not 2 <= len(L["keyPoints"]) <= 5:
        err(lid, "keyPoints should have 2-5 items")
    is_mate_lesson = "mate" in L["title"].lower()

    # worked
    W = L["worked"]
    n = len(W["moves"])
    if len(W["narration"]) != n:
        err(lid, f"worked narration {len(W['narration'])} != moves {n}")
    if len(W["arrows"]) != n:
        err(lid, f"worked arrows {len(W['arrows'])} != moves {n}")
    for per in W["arrows"]:
        for a in per:
            if a["color"] not in COLORS:
                err(lid, f"arrow color {a['color']}")
            for s in (a["from"], a["to"]):
                if s not in chess.SQUARE_NAMES:
                    err(lid, f"arrow square {s}")
    b = board_for(lid, W["fen"], "worked")
    if b and play(lid, b, W["moves"], "worked") and is_mate_lesson and not b.is_checkmate():
        err(lid, "worked example should end in checkmate")

    # faded
    F = L["faded"]
    b = board_for(lid, F["fen"], "faded")
    if b:
        start = b.copy()
        if play(lid, b, F["solution"], "faded"):
            if is_mate_lesson and not b.is_checkmate():
                err(lid, "faded solution should end in checkmate")
            first = chess.Move.from_uci(F["solution"][0])
            themes = set(L["practice"].get("themes", []))
            if "fork" in themes and not is_fork(start, first):
                err(lid, "faded first move is not a fork")
            if "pin" in themes and not has_pin(start, first):
                err(lid, "faded first move creates no pin")
            if "skewer" in themes and not is_skewer(start, first):
                err(lid, "faded first move is not a skewer")
            if "discoveredAttack" in themes and not is_discovered(start, first):
                err(lid, "faded first move is not a discovered attack")
            if L["skill"] == "E2":
                good = [m.uci() for m in start.legal_moves if (lambda x: (x.push(m), catches_pawn(x))[1])(start.copy())]
                if good != [F["solution"][0]]:
                    err(lid, f"square-of-the-pawn moves that catch: {good}")
            if L["skill"] == "E3":
                wins = kpk_winning_moves(start.copy())
                if wins != [F["solution"][0]]:
                    err(lid, f"KPK winning moves {wins}, expected only {F['solution'][0]}")
            if not engine and not is_mate_lesson and L["skill"] not in ("A1", "F1", "E2", "E3"):
                best, _ = best_first_moves(start.copy())
                if best != [first.uci()]:
                    err(lid, f"faded first move {first.uci()} not the unique best by 4-ply search: {best}")
            if engine:
                info = engine.analyse(start, chess.engine.Limit(depth=18), multipv=2)
                best = info[0]["pv"][0]
                if best != first:
                    s_best = info[0]["score"].relative
                    s_ours = engine.analyse(start, chess.engine.Limit(depth=18), root_moves=[first])["score"].relative
                    # Any mate is accepted for mate lessons; otherwise must be within 50cp of best.
                    if not (s_ours.is_mate() and s_ours.mate() > 0) and (s_best.score(mate_score=100000) - s_ours.score(mate_score=100000) > 50):
                        err(lid, f"faded first move {first} not best (engine prefers {best})")

    # practice
    P = L["practice"]
    if P["kind"] not in KINDS:
        err(lid, f"practice kind {P['kind']}")
    if P["kind"] == "puzzles":
        for t in P.get("themes", []):
            if t not in LICHESS_THEMES:
                err(lid, f"unknown Lichess theme {t}")
        if not P.get("themes") or len(P.get("rating", [])) != 2:
            err(lid, "puzzles practice needs themes and rating")
    if P["kind"] == "playout":
        if P.get("goal") not in GOALS:
            err(lid, f"playout goal {P.get('goal')}")
        board_for(lid, P.get("fen", ""), "practice")
    M = L["mastery"]
    if not 0 < M["required"] <= M["of"]:
        err(lid, f"bad mastery {M}")


def check_acyclic(lessons):
    deps = {L["id"]: L["prerequisites"] for L in lessons}
    state = {}

    def visit(n):
        if state.get(n) == 1:
            errors.append(f"[{n}] prerequisite cycle")
            return
        if state.get(n) == 2:
            return
        state[n] = 1
        for d in deps.get(n, []):
            visit(d)
        state[n] = 2

    for n in deps:
        visit(n)


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    data = json.loads(path.read_text())
    assert data["version"] == 1, "version must be 1"
    lessons = data["lessons"]
    ids = [L["id"] for L in lessons]
    if len(ids) != len(set(ids)):
        errors.append("duplicate lesson ids")
    sf = shutil.which("stockfish")
    engine = chess.engine.SimpleEngine.popen_uci(sf) if sf else None
    print(f"stockfish: {sf or 'not found (engine best-move check skipped)'}")
    try:
        for L in lessons:
            check_lesson(L, set(ids), engine)
            print(f"  {L['id']:4} {L['title']:45} worked {len(L['worked']['moves']):2} plies, faded {len(L['faded']['solution'])}, practice {L['practice']['kind']}")
    finally:
        if engine:
            engine.quit()
    check_acyclic(lessons)
    if errors:
        print("\nFAILED:")
        for e in errors:
            print("  " + e)
        sys.exit(1)
    print(f"\nOK: {len(lessons)} lessons valid.")


if __name__ == "__main__":
    main()
