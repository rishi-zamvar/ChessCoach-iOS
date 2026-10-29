"""Minimal App Store Connect API client (team key, ES256 JWT) using only `cryptography` + the stdlib.

Env: ASC_KEY_PATH (the .p8), ASC_KEY_ID, ASC_ISSUER_ID.
"""
from __future__ import annotations

import base64
import json
import os
import time
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

API = "https://api.appstoreconnect.apple.com"
APP_ID = "6823672942"  # Knightlight


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(key_path: str | None = None, key_id: str | None = None, issuer: str | None = None) -> str:
    key_path = key_path or os.environ["ASC_KEY_PATH"]
    key_id = key_id or os.environ["ASC_KEY_ID"]
    issuer = issuer or os.environ["ASC_ISSUER_ID"]
    key = serialization.load_pem_private_key(open(os.path.expanduser(key_path), "rb").read(), password=None)
    header = _b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = _b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    der = key.sign(f"{header}.{payload}".encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return f"{header}.{payload}.{_b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


def call(method: str, path: str, params: dict | None = None, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else API + path
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else {}


def get_all(path: str, params: dict | None = None) -> tuple[list[dict], list[dict]]:
    """All pages of a list endpoint: (data, included)."""
    data, included = [], []
    page = call("GET", path, params)
    while True:
        data += page.get("data", [])
        included += page.get("included", [])
        nxt = page.get("links", {}).get("next")
        if not nxt:
            return data, included
        page = call("GET", nxt)


def testflight_feedback() -> list[dict]:
    """Screenshot feedback for the app, newest first, with build numbers resolved."""
    items, included = get_all(f"/v1/apps/{APP_ID}/betaFeedbackScreenshotSubmissions", {"include": "build", "limit": 200})
    builds = {i["id"]: i["attributes"].get("version", "") for i in included if i["type"] == "builds"}
    for item in items:
        rel = item.get("relationships", {}).get("build", {}).get("data") or {}
        item["build_version"] = builds.get(rel.get("id"), "")
    return items


def as_feedback_rows(items: list[dict]) -> list[dict]:
    """TestFlight submissions in the shape FeedbackStore.add takes (screenshot URL alongside)."""
    rows = []
    for item in items:
        a = item["attributes"]
        rows.append({
            "id": "tf-" + item["id"],
            "category": "none",
            "text": a.get("comment") or "",
            "screen": "",
            "build": "".join(ch for ch in str(item.get("build_version", "")) if ch.isdigit() or ch == "."),
            "app_version": "",
            "context": {"source": "testflight", "device": a.get("deviceModel"), "os": a.get("osVersion"),
                        "locale": a.get("locale"), "created": a.get("createdDate")},
            "breadcrumbs": [],
            "screenshot_url": (a.get("screenshots") or [{}])[0].get("url"),
        })
    return rows
