"""Owner-side feedback triage on the PC (reads the public service's store directly, never over the network).

  python scripts/feedback.py list [--status received]
  python scripts/feedback.py show <id>
  python scripts/feedback.py status <id> fixed --build 63     (or: received / wontfix)
  python scripts/feedback.py notify      # ZeeChat ping per new report; run from Task Scheduler every 10 min
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from public_app.feedback import FeedbackStore  # noqa: E402
from public_app.main import PublicSettings  # noqa: E402


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--data", default=os.environ.get("CHESSCOACH_PUBLIC_DATA", PublicSettings.data_dir))
    sub = p.add_subparsers(dest="cmd", required=True)
    ls = sub.add_parser("list")
    ls.add_argument("--status")
    sub.add_parser("show").add_argument("id")
    st = sub.add_parser("status")
    st.add_argument("id")
    st.add_argument("status", choices=["received", "fixed", "wontfix"])
    st.add_argument("--build")
    sub.add_parser("notify")
    sub.add_parser("deletions")  # deletes queued PostHog persons; needs POSTHOG_PERSONAL_KEY + POSTHOG_PROJECT_ID
    args = p.parse_args()
    store = FeedbackStore(Path(args.data))

    if args.cmd == "list":
        for r in store.all(args.status):
            when = datetime.datetime.fromtimestamp(r["created"]).strftime("%m-%d %H:%M")
            print(f"{r['id'][:8]}  {when}  {r['status']:<8} {r['category']:<9} b{r['build']:<4} {r['screen']:<10} {r['text'][:60]!r}")
    elif args.cmd == "show":
        r = next((r for r in store.all() if r["id"].startswith(args.id)), None)
        if not r:
            sys.exit("no such report")
        r["context"], r["breadcrumbs"] = json.loads(r["context"]), json.loads(r["breadcrumbs"])
        print(json.dumps(r, indent=2))
        shot = store.images / f"{r['id']}.jpg"
        if shot.exists():
            print(f"screenshot: {shot}")
    elif args.cmd == "status":
        r = next((r for r in store.all() if r["id"].startswith(args.id)), None)
        if not r:
            sys.exit("no such report")
        store.set_status(r["id"], args.status, args.build)
    elif args.cmd == "deletions":
        import urllib.parse
        import urllib.request

        key, project = os.environ.get("POSTHOG_PERSONAL_KEY"), os.environ.get("POSTHOG_PROJECT_ID")
        host = os.environ.get("POSTHOG_HOST", "https://eu.posthog.com")
        for d in store.pending_deletions():
            if not (key and project):
                print("pending:", d["distinct_id"], "(set POSTHOG_PERSONAL_KEY and POSTHOG_PROJECT_ID to delete)")
                continue
            q = urllib.parse.urlencode({"distinct_id": d["distinct_id"]})
            req = urllib.request.Request(f"{host}/api/projects/{project}/persons/?{q}", headers={"Authorization": f"Bearer {key}"})
            people = json.load(urllib.request.urlopen(req)).get("results", [])
            for person in people:
                urllib.request.urlopen(urllib.request.Request(
                    f"{host}/api/projects/{project}/persons/{person['id']}/?delete_events=true",
                    method="DELETE", headers={"Authorization": f"Bearer {key}"}))
            store.mark_deleted(d["distinct_id"])
            print("deleted", d["distinct_id"], f"({len(people)} person)")
    elif args.cmd == "notify":
        for r in store.unnotified():
            body = f"[{r['category']}] on {r['screen'] or '?'} (build {r['build']}): {r['text'][:300]}"
            sent = subprocess.run(["dispatchctl", "send", "ceo", "ZeeChat: Knightlight feedback", "--body", body]).returncode == 0
            if sent:
                store.mark_notified(r["id"])


if __name__ == "__main__":
    main()
