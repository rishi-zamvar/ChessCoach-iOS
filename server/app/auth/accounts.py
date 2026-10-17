"""Accounts: one row per Apple ID (`sub`), linked to a chess.com username.

Sign in with Apple happens once, at the start of onboarding. The server
verifies Apple's identity token, then hands the phone its own session
JWT (HS256, long-lived) that it sends as a bearer token from then on.
"""
from __future__ import annotations

import os
import secrets
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path

import jwt

from app.security.secrets_service import SecretsService

ISSUER = "chesscoach-server"
SESSION_TTL_SEC = 365 * 24 * 3600
_KEY_FILENAME = "jwt.key.dpapi"


class SessionError(ValueError):
    """Missing, malformed, expired or forged session token."""


@dataclass
class Account:
    apple_sub: str
    chesscom_username: str | None


class AccountStore:
    def __init__(self, data_dir: Path) -> None:
        data_dir.mkdir(parents=True, exist_ok=True)
        self._dir = data_dir
        self._lock = threading.Lock()
        self._db = sqlite3.connect(data_dir / "accounts.db", check_same_thread=False)
        self._db.execute(
            "CREATE TABLE IF NOT EXISTS accounts ("
            "apple_sub TEXT PRIMARY KEY, chesscom_username TEXT, created_at REAL, updated_at REAL)"
        )
        self._db.commit()
        self._signing_key = self._load_signing_key()

    # MARK: accounts

    def upsert(self, apple_sub: str) -> Account:
        now = time.time()
        with self._lock:
            self._db.execute(
                "INSERT OR IGNORE INTO accounts VALUES (?, NULL, ?, ?)", (apple_sub, now, now)
            )
            self._db.commit()
        return self.get(apple_sub)  # type: ignore[return-value]

    def get(self, apple_sub: str) -> Account | None:
        with self._lock:
            row = self._db.execute(
                "SELECT apple_sub, chesscom_username FROM accounts WHERE apple_sub = ?", (apple_sub,)
            ).fetchone()
        return Account(row[0], row[1]) if row else None

    def link_chesscom(self, apple_sub: str, username: str | None) -> Account:
        with self._lock:
            self._db.execute(
                "UPDATE accounts SET chesscom_username = ?, updated_at = ? WHERE apple_sub = ?",
                (username, time.time(), apple_sub),
            )
            self._db.commit()
        account = self.get(apple_sub)
        if account is None:
            raise SessionError("unknown account")
        return account

    # MARK: session tokens

    def mint(self, apple_sub: str) -> str:
        now = int(time.time())
        return jwt.encode(
            {"iss": ISSUER, "sub": apple_sub, "iat": now, "exp": now + SESSION_TTL_SEC},
            self._signing_key,
            algorithm="HS256",
        )

    def verify(self, token: str) -> Account:
        try:
            claims = jwt.decode(
                token, self._signing_key, algorithms=["HS256"], issuer=ISSUER,
                options={"require": ["sub", "exp", "iss"]},
            )
        except jwt.PyJWTError as e:
            raise SessionError(str(e)) from e
        account = self.get(claims["sub"])
        if account is None:
            raise SessionError("unknown account")
        return account

    def _load_signing_key(self) -> bytes:
        """CHESSCOACH_JWT_SECRET from secrets.enc/env if set; else a random key generated once
        and kept in the data dir, DPAPI-wrapped on Windows."""
        configured = SecretsService.instance().get_optional("CHESSCOACH_JWT_SECRET")
        if configured:
            return configured.encode()
        path = self._dir / _KEY_FILENAME
        if path.exists():
            return _unwrap(path.read_bytes())
        key = secrets.token_bytes(32)
        path.write_bytes(_wrap(key))
        return key


def _wrap(raw: bytes) -> bytes:
    if os.name != "nt":  # dev/tests only; production runs on Windows
        return raw
    from app.security.dpapi import dpapi_protect

    return dpapi_protect(raw)


def _unwrap(blob: bytes) -> bytes:
    if os.name != "nt":
        return blob
    from app.security.dpapi import dpapi_unprotect

    return dpapi_unprotect(blob)
