# /// script
# requires-python = ">=3.11"
# dependencies = ["cryptography>=42"]
# ///
"""App Store Connect chores for Knightlight (spec W7/W8). Key from env: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID.

  uv run scripts/asc.py feedback                    # TestFlight tester feedback (comments + screenshot links)
  uv run scripts/asc.py whattotest 72 "text"        # set a build's "What to Test" notes for testers
  uv run scripts/asc.py analytics request           # one-time: ask Apple for the ongoing analytics reports
  uv run scripts/asc.py analytics download [dir]    # weekly: fetch the newest report files (installs, sessions, crashes…)
"""
from __future__ import annotations

import argparse
import gzip
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server" / "scripts"))
import asc_client as asc  # noqa: E402


def build_id(version: str) -> str:
    data = asc.call("GET", "/v1/builds", {"filter[app]": asc.APP_ID, "filter[version]": version, "limit": 1}).get("data", [])
    if not data:
        sys.exit(f"no build {version}")
    return data[0]["id"]


def what_to_test(version: str, text: str) -> None:
    bid = build_id(version)
    existing = asc.call("GET", f"/v1/builds/{bid}/betaBuildLocalizations").get("data", [])
    if existing:
        asc.call("PATCH", f"/v1/betaBuildLocalizations/{existing[0]['id']}",
                 body={"data": {"type": "betaBuildLocalizations", "id": existing[0]["id"], "attributes": {"whatsNew": text}}})
    else:
        asc.call("POST", "/v1/betaBuildLocalizations", body={"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print(f"What to Test set on build {version}")


def analytics_request() -> None:
    existing = asc.call("GET", f"/v1/apps/{asc.APP_ID}/analyticsReportRequests").get("data", [])
    if any(r["attributes"].get("accessType") == "ONGOING" for r in existing):
        return print("ongoing analytics reports already requested")
    asc.call("POST", "/v1/analyticsReportRequests", body={"data": {
        "type": "analyticsReportRequests", "attributes": {"accessType": "ONGOING"},
        "relationships": {"app": {"data": {"type": "apps", "id": asc.APP_ID}}}}})
    print("requested ongoing analytics reports (Apple generates the first ones within ~48 h)")


def analytics_download(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    requests = asc.call("GET", f"/v1/apps/{asc.APP_ID}/analyticsReportRequests").get("data", [])
    wanted = ("App Store Installation and Deletion", "App Sessions", "App Crashes", "App Store Discovery and Engagement")
    n = 0
    for req in requests:
        reports, _ = asc.get_all(f"/v1/analyticsReportRequests/{req['id']}/reports")
        for report in reports:
            name = report["attributes"].get("name", "")
            if not any(name.startswith(w) for w in wanted):
                continue
            instances = asc.call("GET", f"/v1/analyticsReports/{report['id']}/instances", {"filter[granularity]": "DAILY", "limit": 7}).get("data", [])
            for inst in instances:
                for seg in asc.call("GET", f"/v1/analyticsReportInstances/{inst['id']}/segments").get("data", []):
                    target = out / f"{name}-{inst['attributes'].get('processingDate', inst['id'])}.tsv"
                    if target.exists():
                        continue
                    raw = urllib.request.urlopen(seg["attributes"]["url"], timeout=60).read()
                    target.write_bytes(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)
                    n += 1
    print(f"downloaded {n} report file(s) into {out}")


def main() -> None:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("feedback")
    w = sub.add_parser("whattotest")
    w.add_argument("build")
    w.add_argument("text")
    a = sub.add_parser("analytics")
    a.add_argument("action", choices=["request", "download"])
    a.add_argument("dir", nargs="?", default="build/asc-analytics")
    args = p.parse_args()
    if args.cmd == "feedback":
        for row in asc.as_feedback_rows(asc.testflight_feedback()):
            print(f"[b{row['build']}] {row['context']['created']} {row['context']['device']}: {row['text'].strip()[:200]}")
    elif args.cmd == "whattotest":
        what_to_test(args.build, args.text)
    elif args.action == "request":
        analytics_request()
    else:
        analytics_download(Path(args.dir))


if __name__ == "__main__":
    main()
