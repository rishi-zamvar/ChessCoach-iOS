from __future__ import annotations

import pytest

from app.config import engine_available, get_settings
from app.engines.maia import MaiaEngine

STARTPOS = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

_FAKE_VERBOSE_OUTPUT = """\
info depth 1 seldepth 1 nodes 1
info string e2e4  (174 ) N:       1 (+0.00%) (P: 28.70%) (Q:  0.01) (D:  0.50) (M: 20.1) (S:  0.12) V:  0.01
info string d2d4  (171 ) N:       0 (+0.00%) (P: 25.10%) (Q:  0.00) (D:  0.50) (M: 20.0) (S:  0.10) V:  0.00
info string g1f3  (331 ) N:       0 (+0.00%) (P: 10.00%) (Q:  0.00) (D:  0.50) (M: 19.9) (S:  0.08) V:  0.00
bestmove e2e4
"""


def test_given_verbose_move_stats_when_parsed_then_policy_sums_to_one():
    def fake_runner(cmd: list[str], stdin_text: str) -> str:
        assert "--weights=weights.pb.gz" in cmd
        assert "go nodes 1" in stdin_text
        return _FAKE_VERBOSE_OUTPUT

    engine = MaiaEngine("lc0.exe", "weights.pb.gz", _runner=fake_runner)
    policy = engine.predict(STARTPOS)

    assert set(policy.keys()) == {"e2e4", "d2d4", "g1f3"}
    assert abs(sum(policy.values()) - 1.0) < 1e-9
    assert policy["e2e4"] > policy["d2d4"] > policy["g1f3"]


def test_given_unparseable_output_when_predicted_then_empty_policy():
    def fake_runner(cmd: list[str], stdin_text: str) -> str:
        return "info depth 1\nbestmove e2e4\n"

    engine = MaiaEngine("lc0.exe", "weights.pb.gz", _runner=fake_runner)
    policy = engine.predict(STARTPOS)

    assert policy == {}


@pytest.mark.engine
def test_given_real_lc0_and_maia_weights_when_predicted_then_nonempty_policy():
    settings = get_settings()
    if not (
        engine_available(settings.lc0_path)
        and engine_available(settings.maia_1100_weights_path)
    ):
        pytest.skip("lc0/maia-1100 weights not installed on this host")

    engine = MaiaEngine(settings.lc0_path, settings.maia_1100_weights_path)
    policy = engine.predict(STARTPOS)
    assert policy, "expected at least one move in the policy"
    assert abs(sum(policy.values()) - 1.0) < 1e-6
