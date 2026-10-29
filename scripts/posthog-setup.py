# /// script
# requires-python = ">=3.11"
# ///
"""One-time PostHog setup for Knightlight (spec W7): the two experiment flags and the "Knightlight core"
KPI dashboard. Idempotent: re-running skips what exists.

  POSTHOG_PERSONAL_KEY=phx_... POSTHOG_PROJECT_ID=12345 uv run scripts/posthog-setup.py [--dry-run]
  (POSTHOG_HOST defaults to https://eu.posthog.com)
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request

HOST = os.environ.get("POSTHOG_HOST", "https://eu.posthog.com")
DRY = "--dry-run" in sys.argv

FLAGS = [
  # 50/50: Coach mode as the first-launch default (primary metric D7 retention, guardrail plan completion).
  {"key": "coach_mode_default", "name": "Coach mode is the default puzzle feedback", "rollout": 50},
  # 50/50: completion card shows "Play the coach" first instead of the bonus set.
  {"key": "completion_cta_set", "name": "Completion card: coach game first", "rollout": 50},
]


def trend(name, events, math="dau", display="ActionsLineGraph", interval="day"):
  return {"name": name, "filters": {"insight": "TRENDS", "events": [{"id": e, "math": math} for e in events],
                                    "display": display, "interval": interval, "date_from": "-30d"}}


def funnel(name, steps):
  return {"name": name, "filters": {"insight": "FUNNELS", "events": [{"id": e, "order": i} for i, e in enumerate(steps)],
                                    "funnel_window_days": 1, "date_from": "-30d"}}


def retention(name, start, back):
  return {"name": name, "filters": {"insight": "RETENTION", "target_entity": {"id": start, "type": "events"},
                                    "returning_entity": {"id": back, "type": "events"}, "period": "Day",
                                    "total_intervals": 31, "date_from": "-30d"}}


INSIGHTS = [
  funnel("Activation: first open → onboarding done → first block", ["app.open", "onboarding.done", "plan.block_done"]),
  trend("DAU / WAU", ["app.open"], math="dau"),
  trend("Weekly active", ["app.open"], math="weekly_active"),
  funnel("Plan completion (built → done)", ["plan.built", "plan.done"]),
  funnel("Keeps going after the plan", ["plan.done", "plan.cta"]),
  retention("Retention D1/D7/D30 on finishing a block", "plan.block_done", "plan.block_done"),
  trend("Puzzles by first-try result", ["puzzle.done"], math="total", display="ActionsBar"),
  trend("Coach mode grades", ["puzzle.done"], math="total", display="ActionsPie"),
  trend("Analyze opens", ["analysis.open"], math="dau"),
  trend("AI calls", ["ai.call"], math="total"),
  trend("Dead ends: empty and abandoned blocks", ["plan.block_empty", "plan.block_abandon"], math="total"),
  trend("Feedback sent and thumbs", ["feedback.submit", "feedback.thumb"], math="total", display="ActionsBar"),
  trend("Errors", ["error"], math="total"),
]


def api(method, path, body=None):
  if DRY:
    print(method, path, json.dumps(body)[:120] if body else "")
    return {"results": [], "id": 0}
  req = urllib.request.Request(f"{HOST}/api/projects/{os.environ['POSTHOG_PROJECT_ID']}{path}", method=method,
                               data=json.dumps(body).encode() if body else None,
                               headers={"Authorization": f"Bearer {os.environ['POSTHOG_PERSONAL_KEY']}", "Content-Type": "application/json"})
  with urllib.request.urlopen(req, timeout=30) as r:
    return json.loads(r.read() or b"{}")


def main():
  if not DRY and not (os.environ.get("POSTHOG_PERSONAL_KEY") and os.environ.get("POSTHOG_PROJECT_ID")):
    sys.exit("set POSTHOG_PERSONAL_KEY and POSTHOG_PROJECT_ID (or pass --dry-run)")
  flags = {f["key"] for f in api("GET", "/feature_flags/?limit=200").get("results", [])}
  for f in FLAGS:
    if f["key"] in flags:
      continue
    api("POST", "/feature_flags/", {"key": f["key"], "name": f["name"], "active": True,
                                    "filters": {"groups": [{"properties": [], "rollout_percentage": f["rollout"]}]}})
    print("flag", f["key"])
  boards = [d for d in api("GET", "/dashboards/?limit=200").get("results", []) if d.get("name") == "Knightlight core"]
  board = boards[0] if boards else api("POST", "/dashboards/", {"name": "Knightlight core", "description": "Spec W7 KPIs"})
  for insight in INSIGHTS:
    api("POST", "/insights/", {**insight, "dashboards": [board.get("id")]})
  print(f"dashboard Knightlight core with {len(INSIGHTS)} insights")


if __name__ == "__main__":
  main()
