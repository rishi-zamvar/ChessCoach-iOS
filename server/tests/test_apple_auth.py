"""Sign in with Apple once -> session JWT -> link a chess.com username."""
from __future__ import annotations

import json
import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

from app.auth import apple_signin
from app.config import Settings
from tests.conftest import NON_OWNER_IP, make_client

BUNDLE = "com.rishizamvar.chesscoach"


@pytest.fixture
def apple_key(monkeypatch, tmp_path):
    """Stands in for Apple: our own RSA key served as the JWKS."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = json.loads(RSAAlgorithm.to_jwk(key.public_key()))
    jwk["kid"] = "test-kid"
    monkeypatch.setattr(apple_signin, "_fetch_jwks", lambda force=False: {"keys": [jwk]})
    return key


def apple_token(key, *, sub="apple-user-1", aud=BUNDLE, iss="https://appleid.apple.com", exp_in=600) -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": iss, "aud": aud, "sub": sub, "iat": now, "exp": now + exp_in},
        key, algorithm="RS256", headers={"kid": "test-kid"},
    )


def test_given_valid_apple_token_when_signing_in_then_session_token_then_links_chesscom_and_remembers_it(owner_client, apple_key):
    r = owner_client.post("/auth/apple", json={"identity_token": apple_token(apple_key)})
    assert r.status_code == 200
    body = r.json()
    assert body["chesscom_username"] is None
    session = body["token"]

    r = owner_client.put("/account", json={"chesscom_username": "Zammy009"}, headers={"Authorization": f"Bearer {session}"})
    assert r.status_code == 200 and r.json()["chesscom_username"] == "Zammy009"

    # Signing in again (new phone, reinstall) brings the username back.
    again = owner_client.post("/auth/apple", json={"identity_token": apple_token(apple_key)}).json()
    assert again["chesscom_username"] == "Zammy009"


@pytest.mark.parametrize(
    "kwargs", [{"aud": "com.someone.else"}, {"iss": "https://evil.example"}, {"exp_in": -60}]
)
def test_given_bad_apple_token_when_signing_in_then_401(owner_client, apple_key, kwargs):
    r = owner_client.post("/auth/apple", json={"identity_token": apple_token(apple_key, **kwargs)})
    assert r.status_code == 401


def test_given_token_signed_by_other_key_when_signing_in_then_401(owner_client, apple_key):
    forger = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    r = owner_client.post("/auth/apple", json={"identity_token": apple_token(forger)})
    assert r.status_code == 401


def test_given_missing_or_forged_session_when_linking_then_401(owner_client, apple_key):
    assert owner_client.put("/account", json={"chesscom_username": "x"}).status_code == 401
    forged = jwt.encode({"iss": "chesscoach-server", "sub": "apple-user-1", "exp": int(time.time()) + 60}, "guess", algorithm="HS256")
    r = owner_client.put("/account", json={"chesscom_username": "x"}, headers={"Authorization": f"Bearer {forged}"})
    assert r.status_code == 401


def test_given_stranger_on_tailnet_when_signing_in_then_403(app, apple_key):
    with make_client(app, NON_OWNER_IP) as c:
        assert c.post("/auth/apple", json={"identity_token": apple_token(apple_key)}).status_code == 403


def test_given_restart_when_verifying_old_session_then_still_valid(no_engine_settings: Settings, apple_key):
    from pathlib import Path

    from app.auth.accounts import AccountStore

    first = AccountStore(Path(no_engine_settings.data_dir))
    first.upsert("apple-user-1")
    token = first.mint("apple-user-1")
    assert AccountStore(Path(no_engine_settings.data_dir)).verify(token).apple_sub == "apple-user-1"
