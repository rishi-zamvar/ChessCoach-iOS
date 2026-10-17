"""Apple Sign-In identity_token validation (ported from workoutcoach-backend).

iOS Sign in with Apple returns an identity_token that's a JWT signed
with one of Apple's published keys. We verify by:
  1. Fetch Apple's JWKS from https://appleid.apple.com/auth/keys
     (cached for APPLE_KEYS_TTL_SEC).
  2. Decode the token header to find the kid (key id).
  3. Verify signature against the matching JWK + RS256.
  4. Check `iss == https://appleid.apple.com`.
  5. Check `aud == settings.apple_bundle_id`.
  6. Check `exp > now`.

apple_bundle_id MUST be set in settings or this function refuses to
run (caller turns that into a 503).
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Any

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey
from jwt.algorithms import RSAAlgorithm

from app.config import Settings

log = logging.getLogger(__name__)

_APPLE_JWKS_URL: str = "https://appleid.apple.com/auth/keys"
_APPLE_ISSUER: str = "https://appleid.apple.com"
_APPLE_KEYS_TTL_SEC: float = 60 * 60  # cache for 1 hour

# Mutable container so module-level state can be updated without `global`.
# Persisted to disk so the JWKS survives
# a service restart — keeps first /auth/apple after restart from blocking
# on a 1-3s HTTPS round-trip to Apple. fetched_at uses time.time() (wall
# clock) since the persisted value must compare meaningfully across
# process lifetimes. Path settable via APPLE_JWKS_CACHE_PATH env;
# default %ProgramData%\\zee-platform\\chesscoach\\apple_jwks_cache.json.
_jwks_state: dict[str, Any] = {"keys": {}, "fetched_at": 0.0}
_jwks_lock = threading.Lock()
_jwks_loaded = False


class AppleSignInError(ValueError):
    """Raised when the identity_token is invalid for any reason."""


def _jwks_persist_path() -> Path:
    p = os.environ.get("APPLE_JWKS_CACHE_PATH")
    if p:
        return Path(p)
    base = Path(os.environ.get("PROGRAMDATA", r"C:\ProgramData"))
    return base / "zee-platform" / "chesscoach" / "apple_jwks_cache.json"


def _load_jwks_from_disk() -> None:
    """Best-effort: load persisted JWKS on first access. No-op on errors.
    If the persisted entry is past its TTL, drop it so the next call
    triggers a fresh fetch."""
    global _jwks_loaded
    if _jwks_loaded:
        return
    _jwks_loaded = True
    path = _jwks_persist_path()
    try:
        if not path.exists():
            return
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return
        fetched_at = float(data.get("fetched_at") or 0.0)
        keys = data.get("keys")
        if not isinstance(keys, dict) or not keys:
            return
        if (time.time() - fetched_at) >= _APPLE_KEYS_TTL_SEC:
            return  # stale — next fetch will refresh
        _jwks_state["keys"] = keys
        _jwks_state["fetched_at"] = fetched_at
        log.info("apple_signin: loaded JWKS cache from %s", path)
    except Exception as exc:  # noqa: BLE001
        log.warning("apple_signin: JWKS load failed (%s): %s", path, exc)


def _flush_jwks_to_disk() -> None:
    """Best-effort persist. Caller holds _jwks_lock."""
    path = _jwks_persist_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(_jwks_state), encoding="utf-8")
        tmp.replace(path)
    except Exception as exc:  # noqa: BLE001
        log.warning("apple_signin: JWKS flush failed (%s): %s", path, exc)


def _fetch_jwks(force: bool = False) -> dict[str, Any]:
    with _jwks_lock:
        _load_jwks_from_disk()
        now = time.time()
        if (
            not force
            and _jwks_state["keys"]
            and (now - _jwks_state["fetched_at"]) < _APPLE_KEYS_TTL_SEC
        ):
            return _jwks_state["keys"]  # type: ignore[no-any-return]
    # Network IO outside the lock — other readers can still serve the
    # cached copy concurrently. The lock is reacquired for the write.
    with httpx.Client(timeout=3.0) as client:
        r = client.get(_APPLE_JWKS_URL)
        r.raise_for_status()
        payload = r.json()
    with _jwks_lock:
        _jwks_state["keys"] = payload
        _jwks_state["fetched_at"] = time.time()
        _flush_jwks_to_disk()
        return _jwks_state["keys"]  # type: ignore[no-any-return]


def _find_key(jwks: dict[str, Any], kid: str) -> dict[str, Any] | None:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key  # type: ignore[no-any-return]
    return None


def verify_identity_token(token: str, settings: Settings) -> dict[str, Any]:
    """Return the decoded + verified claims. Raises AppleSignInError on
    any validation failure."""
    if not settings.apple_bundle_id:
        raise AppleSignInError(
            "APPLE_BUNDLE_ID is unset; Apple Sign-In is not configured on this backend"
        )

    try:
        header = jwt.get_unverified_header(token)
    except Exception as e:
        raise AppleSignInError(f"unparseable token header: {e}") from e

    kid = header.get("kid")
    if not kid:
        raise AppleSignInError("token header missing 'kid'")

    try:
        jwks = _fetch_jwks()
    except httpx.HTTPError as e:
        raise AppleSignInError(f"could not fetch Apple JWKS: {e}") from e

    raw_key = _find_key(jwks, kid)
    if raw_key is None:
        # Apple may have rotated keys; force-refresh once.
        try:
            jwks = _fetch_jwks(force=True)
        except httpx.HTTPError as e:
            raise AppleSignInError(f"could not refresh Apple JWKS: {e}") from e
        raw_key = _find_key(jwks, kid)
        if raw_key is None:
            raise AppleSignInError(f"no Apple key matches kid={kid}")

    # PyJWT's decode verifies the signature itself when given the
    # algorithm + key. RSAAlgorithm.from_jwk takes a JWK dict (or
    # JSON string) and returns a key object decode() accepts directly.
    try:
        public_key = RSAAlgorithm.from_jwk(json.dumps(raw_key))
    except Exception as e:
        raise AppleSignInError(f"could not construct Apple JWK: {e}") from e
    if not isinstance(public_key, RSAPublicKey):
        # Apple's JWKS only ever contains public RSA keys. Anything else
        # is either a misconfiguration or an attacker-crafted blob.
        raise AppleSignInError("Apple JWK did not yield an RSA public key")

    try:
        claims: dict[str, Any] = jwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            audience=settings.apple_bundle_id,
            issuer=_APPLE_ISSUER,
        )
    except Exception as e:
        raise AppleSignInError(f"claim verification failed: {e}") from e

    return claims
