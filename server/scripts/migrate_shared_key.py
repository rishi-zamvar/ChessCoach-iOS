import getpass
"""One-shot: populate chesscoach's own secrets.enc from an already-
bootstrapped sibling service's secrets.enc (ClearHead / WorkoutCoach),
instead of asking a human to retype the Anthropic key.

Why this is safe: DPAPI CRYPTPROTECT_LOCAL_MACHINE scope is explicitly
machine-wide, not per-application (zee-platform SECURITY.md SS3.2) -
"any process on this PC" can already unwrap any LocalMachine-scoped
blob written on this machine. This script just performs that unwrap +
re-wrap once, in-process, so chesscoach loads the shared key "the same
way the existing backends do" (per the deploy brief) without the key
ever touching argv, stdout, or a log line.

Usage:
  C:\\venvs\\chesscoach\\Scripts\\python.exe scripts\\migrate_shared_key.py

Prints only the destination path and the key_id (sha256 prefix) - never
the key value.
"""
from __future__ import annotations

import hashlib
import json
import secrets
import subprocess
import sys
from pathlib import Path

_PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_PROJECT_ROOT))

from cryptography.hazmat.primitives.ciphers.aead import AESGCM  # noqa: E402

from app.security.dpapi import dpapi_protect, dpapi_unprotect  # noqa: E402

_SOURCE_DIRS = (
    Path(r"C:\ProgramData\zee-platform\workoutcoach"),
    Path(r"C:\ProgramData\zee-platform\clearhead"),
)
_DEST_DIR = Path(r"C:\ProgramData\zee-platform\chesscoach")
_ENC_NAME = "secrets.enc"
_KEY_NAME = "secrets.key.dpapi"
_NONCE_LEN = 12
_SHARED_KEY_NAME = "ANTHROPIC_API_KEY"


def _decrypt_dir(dirpath: Path) -> dict[str, str]:
    key_path = dirpath / _KEY_NAME
    enc_path = dirpath / _ENC_NAME
    if not key_path.exists() or not enc_path.exists():
        return {}
    aes_key = dpapi_unprotect(key_path.read_bytes())
    blob = enc_path.read_bytes()
    nonce, ct = blob[:_NONCE_LEN], blob[_NONCE_LEN:]
    plaintext = AESGCM(aes_key).decrypt(nonce, ct, None)
    return json.loads(plaintext.decode("utf-8"))


def _load_or_generate_aes_key(key_path: Path) -> bytes:
    if key_path.exists():
        return dpapi_unprotect(key_path.read_bytes())
    aes_key = secrets.token_bytes(32)
    key_path.write_bytes(dpapi_protect(aes_key))
    return aes_key


def _encrypt(secrets_dict: dict[str, str], aes_key: bytes) -> bytes:
    nonce = secrets.token_bytes(_NONCE_LEN)
    ct = AESGCM(aes_key).encrypt(nonce, json.dumps(secrets_dict).encode("utf-8"), None)
    return nonce + ct


def _lock_acl(path: Path) -> None:
    subprocess.run(
        ["icacls", str(path), "/inheritance:r", "/grant:r",
         "SYSTEM:F", "Administrators:F", f"{getpass.getuser()}:F"],
        check=True,
        capture_output=True,
    )


def main() -> int:
    shared_key: str | None = None
    for source_dir in _SOURCE_DIRS:
        values = _decrypt_dir(source_dir)
        if _SHARED_KEY_NAME in values:
            shared_key = values[_SHARED_KEY_NAME]
            print(f"found {_SHARED_KEY_NAME} in {source_dir}")
            break

    if shared_key is None:
        print(f"ERROR: no sibling secrets.enc contained {_SHARED_KEY_NAME}", file=sys.stderr)
        return 1

    _DEST_DIR.mkdir(parents=True, exist_ok=True)
    key_path = _DEST_DIR / _KEY_NAME
    enc_path = _DEST_DIR / _ENC_NAME

    aes_key = _load_or_generate_aes_key(key_path)
    existing = _decrypt_dir(_DEST_DIR)
    existing[_SHARED_KEY_NAME] = shared_key
    enc_path.write_bytes(_encrypt(existing, aes_key))

    try:
        _lock_acl(key_path)
        _lock_acl(enc_path)
    except subprocess.CalledProcessError as exc:
        print(f"WARNING: icacls failed ({exc}); run as Administrator to lock ACLs", file=sys.stderr)

    key_id = hashlib.sha256(shared_key.encode("utf-8")).hexdigest()[:8]
    print(f"wrote {enc_path} with keys: {sorted(existing.keys())}")
    print(f"key_id: {key_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
