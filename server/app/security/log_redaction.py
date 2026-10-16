"""Log redaction, ported from workoutcoach-backend (SECURITY.md SS9.1).

A logging.Filter subclass that masks any currently-loaded secret VALUE
(pulled from SecretsService at filter init) out of every formatted log
record. This is the defense-in-depth backstop: application code should
never pass the Anthropic key itself into a log call (only `key_id`,
the first 8 hex of sha256(key)), but this filter catches it even if
that discipline slips.
"""
from __future__ import annotations

import logging

from app.security.secrets_service import SecretsService

_REDACTED = "[REDACTED]"
_INSTALLED_SENTINEL = "_cc_redaction_installed"


class RedactingFilter(logging.Filter):
    def __init__(self) -> None:
        super().__init__()
        self._exact_values: tuple[str, ...] = self._load_secret_values()

    def _load_secret_values(self) -> tuple[str, ...]:
        svc = SecretsService.instance()
        values: list[str] = []
        for key in svc.loaded_keys():
            try:
                v = svc.get(key)
                if isinstance(v, str) and len(v) >= 16:
                    values.append(v)
            except KeyError:
                continue
        return tuple(values)

    def filter(self, record: logging.LogRecord) -> bool:
        if record.name.startswith("uvicorn.access"):
            return True
        msg = record.getMessage()
        for v in self._exact_values:
            if v in msg:
                msg = msg.replace(v, _REDACTED)
        record.msg = msg
        record.args = ()
        return True


def install() -> None:
    root = logging.getLogger()
    if getattr(root, _INSTALLED_SENTINEL, False):
        return
    root.addFilter(RedactingFilter())
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error", "app"):
        logging.getLogger(name).addFilter(RedactingFilter())
    setattr(root, _INSTALLED_SENTINEL, True)
