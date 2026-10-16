"""Owner-only tailscale-whois auth dependency.

Every request is gated by resolving the caller's tailnet identity via
`tailscale whois --json <peer-ip>` and checking that the resolved
login matches the single owner login configured for this PC. There is
no bearer token - the phone client never stores a secret (PLAN.md
"Hard requirements" #2).

Results are cached for 5 minutes per source IP (PLAN.md: "cache it for
5 minutes") since `tailscale whois` shells out to a subprocess on
every call and the owner's devices poll /health frequently.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Callable

from fastapi import HTTPException, Request, status

from app.security import tailscale

CACHE_TTL_SECONDS = 300.0

import os

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover
    load_dotenv = None  # type: ignore[assignment]


def owner_login_from_env() -> str:
    """The one tailnet login allowed to call this service: CHESSCOACH_OWNER_LOGIN from the
    environment or the gitignored .env (kept out of the repo). Empty means deny everyone."""
    if load_dotenv is not None:
        load_dotenv(override=False)
    return os.environ.get("CHESSCOACH_OWNER_LOGIN", "").strip()


@dataclass
class _CacheEntry:
    info: tailscale.WhoisInfo | None
    expires_at: float


class WhoisAuthenticator:
    """Instantiate one per app (or per test) so the cache + owner login
    + runner are all injectable instead of module-global."""

    def __init__(
        self,
        *,
        owner_login: str | None = None,
        whois_runner: Callable[[list[str]], str] | None = None,
        ttl_seconds: float = CACHE_TTL_SECONDS,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._owner_login = owner_login if owner_login is not None else owner_login_from_env()
        self._runner = whois_runner or tailscale._default_runner
        self._ttl = ttl_seconds
        self._clock = clock
        self._cache: dict[str, _CacheEntry] = {}

    def _resolve(self, ip: str) -> tailscale.WhoisInfo | None:
        now = self._clock()
        cached = self._cache.get(ip)
        if cached is not None and cached.expires_at > now:
            return cached.info
        try:
            info = tailscale.whois(ip, _runner=self._runner)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"tailscale whois infra unavailable: {exc}",
                headers={"Retry-After": "2"},
            ) from exc
        self._cache[ip] = _CacheEntry(info=info, expires_at=now + self._ttl)
        return info

    def __call__(self, request: Request) -> None:
        """FastAPI dependency: raises 403 unless the caller is the owner."""
        client_host = request.client.host if request.client else ""
        if not client_host:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "no client IP for whois")
        info = self._resolve(client_host)
        if info is None:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN, f"whois failed for client {client_host!r}"
            )
        if info.user != self._owner_login:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                f"login {info.user!r} is not the configured owner",
            )
