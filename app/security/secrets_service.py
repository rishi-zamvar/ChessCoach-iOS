"""SecretsService: at-rest secrets per zee-platform SECURITY.md SS3.2.

Same mechanism as workoutcoach-backend / clearhead-backend: a singleton
that loads `secrets.enc` once at boot, AES-GCM-256 decrypted with a key
unwrapped from the Windows DPAPI store (LocalMachine scope). Callers use
`SecretsService.instance().get(...)` and never read os.environ directly
for the sensitive surface.

Fallback chain on .get():
  1. value loaded from secrets.enc at boot
  2. value from os.environ (dev / tests / fresh install before bootstrap)
  3. KeyError (no recovery)

File layout (Windows, LocalSystem service):
  C:\\ProgramData\\zee-platform\\chesscoach\\
    secrets.enc         - AES-GCM(nonce || ciphertext || tag)
    secrets.key.dpapi   - DPAPI-LocalMachine-wrapped 32-byte AES key.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.security.dpapi import dpapi_unprotect

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover - dev / test only
    load_dotenv = None  # type: ignore[assignment]

_log = logging.getLogger(__name__)

_DEFAULT_SECRETS_DIR = Path(r"C:\ProgramData\zee-platform\chesscoach")
_ENC_FILENAME = "secrets.enc"
_KEY_FILENAME = "secrets.key.dpapi"

# AES-GCM nonce is 12 bytes per NIST SP 800-38D.
_NONCE_LEN = 12

# ChessCoach prefers a service-specific key if one has been configured,
# else falls back to the shared key used by the other Claude-backed
# services on this PC (ClearHead, WorkoutCoach).
ANTHROPIC_KEY_NAME_PREFERRED = "ANTHROPIC_API_KEY_CHESSCOACH"
ANTHROPIC_KEY_NAME_SHARED = "ANTHROPIC_API_KEY"


class SecretsService:
    """Process-wide singleton. Use `SecretsService.instance()` rather
    than constructing directly. Tests can swap in a controlled
    instance via `SecretsService.reset_for_tests(secrets_dict)`."""

    _instance: SecretsService | None = None
    _instance_lock = threading.Lock()

    def __init__(self, secrets_dir: Path | None = None) -> None:
        self._secrets_dir = secrets_dir or self._default_secrets_dir()
        self._loaded: dict[str, str] | None = None

    @classmethod
    def instance(cls) -> SecretsService:
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = cls()
                cls._instance._load_if_needed()
        return cls._instance

    @classmethod
    def reset_for_tests(cls, secrets: dict[str, str] | None = None) -> None:
        """Replace the singleton with a controlled in-memory instance.
        Pass None to force a fresh load on the next .instance() call."""
        with cls._instance_lock:
            if secrets is None:
                cls._instance = None
                return
            svc = cls()
            svc._loaded = dict(secrets)
            cls._instance = svc

    def get(self, key: str) -> str:
        """Return the secret value or raise KeyError. Never log the
        value itself - only key names / key_id are safe to log."""
        self._load_if_needed()
        if self._loaded and key in self._loaded:
            return self._loaded[key]
        env_val = os.environ.get(key)
        if env_val is not None:
            return env_val
        raise KeyError(f"secret {key!r} not configured (not in secrets.enc, not in env)")

    def get_optional(self, key: str) -> str | None:
        try:
            return self.get(key)
        except KeyError:
            return None

    def get_anthropic_key(self) -> str | None:
        """Prefer ANTHROPIC_API_KEY_CHESSCOACH; fall back to the shared
        ANTHROPIC_API_KEY used by ClearHead/WorkoutCoach. Returns None
        if neither is configured (caller maps this to 503)."""
        preferred = self.get_optional(ANTHROPIC_KEY_NAME_PREFERRED)
        if preferred:
            return preferred
        return self.get_optional(ANTHROPIC_KEY_NAME_SHARED)

    @property
    def secrets_dir(self) -> Path:
        return self._secrets_dir

    @property
    def is_loaded_from_disk(self) -> bool:
        return self._loaded is not None and bool(self._loaded)

    def loaded_keys(self) -> list[str]:
        """Safe to log - key NAMES only, never values."""
        self._load_if_needed()
        return sorted(self._loaded.keys()) if self._loaded else []

    def _default_secrets_dir(self) -> Path:
        env_override = os.environ.get("CC_SECRETS_DIR")
        if env_override:
            return Path(env_override)
        return _DEFAULT_SECRETS_DIR

    def _load_if_needed(self) -> None:
        if self._loaded is not None:
            return
        if load_dotenv is not None:
            load_dotenv(override=False)

        enc_path = self._secrets_dir / _ENC_FILENAME
        key_path = self._secrets_dir / _KEY_FILENAME
        if not enc_path.exists() or not key_path.exists():
            self._loaded = {}
            _log.info(
                "SecretsService: no secrets.enc at %s; running on env-var fallback",
                self._secrets_dir,
            )
            return
        try:
            wrapped_key = key_path.read_bytes()
            aes_key = dpapi_unprotect(wrapped_key)
            ciphertext = enc_path.read_bytes()
            nonce, ct = ciphertext[:_NONCE_LEN], ciphertext[_NONCE_LEN:]
            plaintext = AESGCM(aes_key).decrypt(nonce, ct, None)
            self._loaded = json.loads(plaintext.decode("utf-8"))
            _log.info(
                "SecretsService: loaded %d keys from %s",
                len(self._loaded),
                enc_path.name,
            )
        except Exception as exc:
            _log.error(
                "SecretsService: failed to decrypt %s (%s); using env fallback",
                enc_path.name,
                type(exc).__name__,
            )
            self._loaded = {}
