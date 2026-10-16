"""Windows DPAPI wrapper (LocalMachine scope).

CryptProtectData / CryptUnprotectData via ctypes, no extra deps.
Used by SecretsService to wrap the AES-GCM-256 master key for
secrets.enc. LocalMachine scope means the wrapped blob can be
decrypted by ANY process on this PC (including the NSSM
LocalSystem service) but cannot be exfiltrated to another machine
- DPAPI is bound to the machine's TPM/DPAPI master.

Copied verbatim from workoutcoach-backend/app/security/dpapi.py
(zee-platform SECURITY.md SS3.2 pattern) so chesscoach-server loads
secrets the same way the existing backends do.
"""

from __future__ import annotations

import ctypes
from ctypes import wintypes

CRYPTPROTECT_LOCAL_MACHINE = 0x4


class _DATA_BLOB(ctypes.Structure):
    _fields_ = [
        ("cbData", wintypes.DWORD),
        ("pbData", ctypes.POINTER(ctypes.c_byte)),
    ]


_crypt32 = ctypes.windll.crypt32 if hasattr(ctypes, "windll") else None
_kernel32 = ctypes.windll.kernel32 if hasattr(ctypes, "windll") else None


def _blob_in(data: bytes) -> _DATA_BLOB:
    buf = ctypes.create_string_buffer(data, len(data))
    return _DATA_BLOB(
        cbData=len(data),
        pbData=ctypes.cast(buf, ctypes.POINTER(ctypes.c_byte)),
    )


def _blob_out_bytes(blob: _DATA_BLOB) -> bytes:
    data = ctypes.string_at(blob.pbData, blob.cbData)
    if _kernel32 is not None:
        _kernel32.LocalFree(blob.pbData)
    return data


def dpapi_protect(plaintext: bytes) -> bytes:
    """Wrap `plaintext` with the LocalMachine DPAPI master."""
    if _crypt32 is None:
        raise RuntimeError("DPAPI unavailable (non-Windows host)")
    in_blob = _blob_in(plaintext)
    out_blob = _DATA_BLOB()
    ok = _crypt32.CryptProtectData(
        ctypes.byref(in_blob),
        None,
        None,
        None,
        None,
        CRYPTPROTECT_LOCAL_MACHINE,
        ctypes.byref(out_blob),
    )
    if not ok:
        raise OSError(f"CryptProtectData failed (GetLastError={ctypes.GetLastError()})")
    return _blob_out_bytes(out_blob)


def dpapi_unprotect(ciphertext: bytes) -> bytes:
    """Unwrap a blob previously sealed with dpapi_protect on THIS machine."""
    if _crypt32 is None:
        raise RuntimeError("DPAPI unavailable (non-Windows host)")
    in_blob = _blob_in(ciphertext)
    out_blob = _DATA_BLOB()
    ok = _crypt32.CryptUnprotectData(
        ctypes.byref(in_blob),
        None,
        None,
        None,
        None,
        CRYPTPROTECT_LOCAL_MACHINE,
        ctypes.byref(out_blob),
    )
    if not ok:
        raise OSError(f"CryptUnprotectData failed (GetLastError={ctypes.GetLastError()})")
    return _blob_out_bytes(out_blob)
