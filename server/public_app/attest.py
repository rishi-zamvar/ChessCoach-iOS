"""Apple App Attest: proves a request comes from a genuine install of the ChessCoach app.

Two steps (https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server):
1. Attestation, once per install: the app's Secure Enclave key is certified by Apple for our
   app ID. We check the certificate chain up to Apple's App Attestation root, the challenge
   nonce, the app ID hash and the key id, then keep the public key.
2. Assertion, on every request: the app signs (authenticatorData, hash of the request) with that
   key. We check the signature, the app ID hash and that the counter only goes up.
"""
from __future__ import annotations

import datetime
import hashlib
from dataclasses import dataclass
from pathlib import Path

import cbor2
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

NONCE_OID = x509.ObjectIdentifier("1.2.840.113635.100.8.2")
NONCE_DER_PREFIX = bytes.fromhex("3024a1220420")
AAGUID_PRODUCTION = b"appattest" + b"\x00" * 7
AAGUID_DEVELOPMENT = b"appattestdevelop"
APPLE_ROOT_PEM = (Path(__file__).parent / "apple_app_attest_root.pem").read_bytes()


class AttestError(ValueError):
    """The attestation or assertion is not valid."""


@dataclass
class AttestedKey:
    key_id: bytes
    public_key_pem: bytes
    counter: int


class AppAttestVerifier:
    def __init__(self, app_id: str, root_pem: bytes = APPLE_ROOT_PEM) -> None:
        """`app_id` is "<TeamID>.<bundle id>"."""
        self.rp_id_hash = hashlib.sha256(app_id.encode()).digest()
        self.root = x509.load_pem_x509_certificate(root_pem)

    # MARK: attestation

    def verify_attestation(self, key_id: bytes, attestation: bytes, challenge: bytes, now: datetime.datetime | None = None) -> AttestedKey:
        now = now or datetime.datetime.now(datetime.timezone.utc)
        try:
            obj = cbor2.loads(attestation)
            stmt, auth_data = obj["attStmt"], obj["authData"]
            if obj.get("fmt") != "apple-appattest":
                raise AttestError("wrong format")
            certs = [x509.load_der_x509_certificate(der) for der in stmt["x5c"]]
        except AttestError:
            raise
        except Exception as e:  # malformed CBOR / certs
            raise AttestError(f"unreadable attestation: {e}") from e
        if len(certs) < 2:
            raise AttestError("certificate chain too short")
        leaf, intermediate = certs[0], certs[1]
        self._check_chain(leaf, intermediate, now)

        # The leaf certifies a nonce = SHA256(authData || SHA256(challenge)).
        nonce = hashlib.sha256(auth_data + hashlib.sha256(challenge).digest()).digest()
        try:
            ext = leaf.extensions.get_extension_for_oid(NONCE_OID).value.value
        except x509.ExtensionNotFound as e:
            raise AttestError("no nonce extension") from e
        if ext != NONCE_DER_PREFIX + nonce:  # DER: SEQUENCE { [1] { OCTET STRING (32) nonce } }
            raise AttestError("nonce mismatch")

        public_key = leaf.public_key()
        if not isinstance(public_key, ec.EllipticCurvePublicKey):
            raise AttestError("not an EC key")
        point = public_key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
        if hashlib.sha256(point).digest() != key_id:
            raise AttestError("key id does not match the certified key")

        rp_id_hash, counter, aaguid, cred_id = self._parse_auth_data(auth_data, attested=True)
        if rp_id_hash != self.rp_id_hash:
            raise AttestError("wrong app id")
        if counter != 0:
            raise AttestError("counter must start at 0")
        if aaguid not in (AAGUID_PRODUCTION, AAGUID_DEVELOPMENT):
            raise AttestError("wrong aaguid")
        if cred_id != key_id:
            raise AttestError("credential id does not match key id")
        pem = public_key.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        return AttestedKey(key_id=key_id, public_key_pem=pem, counter=0)

    def _check_chain(self, leaf: x509.Certificate, intermediate: x509.Certificate, now: datetime.datetime) -> None:
        for cert, issuer in ((leaf, intermediate), (intermediate, self.root)):
            if not (cert.not_valid_before_utc <= now <= cert.not_valid_after_utc):
                raise AttestError("certificate expired or not yet valid")
            try:
                cert.verify_directly_issued_by(issuer)
            except (ValueError, TypeError, InvalidSignature) as e:
                raise AttestError("certificate chain does not lead to Apple's root") from e

    # MARK: assertion

    def verify_assertion(self, key: AttestedKey, assertion: bytes, client_data: bytes) -> int:
        """Checks one request's assertion; returns the new counter (store it)."""
        try:
            obj = cbor2.loads(assertion)
            signature, auth_data = obj["signature"], obj["authenticatorData"]
        except Exception as e:
            raise AttestError(f"unreadable assertion: {e}") from e
        nonce = hashlib.sha256(auth_data + hashlib.sha256(client_data).digest()).digest()
        public_key = serialization.load_pem_public_key(key.public_key_pem)
        assert isinstance(public_key, ec.EllipticCurvePublicKey)
        try:
            public_key.verify(signature, nonce, ec.ECDSA(hashes.SHA256()))
        except InvalidSignature as e:
            raise AttestError("bad signature") from e
        rp_id_hash, counter, _, _ = self._parse_auth_data(auth_data, attested=False)
        if rp_id_hash != self.rp_id_hash:
            raise AttestError("wrong app id")
        if counter <= key.counter:
            raise AttestError("replayed or out-of-order request")
        return counter

    @staticmethod
    def _parse_auth_data(data: bytes, attested: bool) -> tuple[bytes, int, bytes, bytes]:
        if len(data) < 37:
            raise AttestError("authenticator data too short")
        rp_id_hash, counter = data[:32], int.from_bytes(data[33:37], "big")
        if not attested:
            return rp_id_hash, counter, b"", b""
        if len(data) < 55:
            raise AttestError("attested data too short")
        aaguid = data[37:53]
        length = int.from_bytes(data[53:55], "big")
        return rp_id_hash, counter, aaguid, data[55 : 55 + length]
