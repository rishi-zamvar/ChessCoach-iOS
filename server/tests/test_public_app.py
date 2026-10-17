"""The internet-facing service: only genuine app installs, only analysis + Maia, nothing else."""
from __future__ import annotations

import base64
import datetime
import hashlib
import time
from pathlib import Path

import cbor2
import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
from fastapi.testclient import TestClient

from public_app import main as public_main
from public_app.attest import AAGUID_PRODUCTION, NONCE_DER_PREFIX, NONCE_OID, AppAttestVerifier
from tests.conftest import FakeAnalysisEngine

APP_ID = public_main.APP_ID
PGN = '[Event "t"]\n\n1. e4 e5 2. Nf3 Nc6 *'


def _cert(subject: str, key, issuer_name: str, issuer_key, ca: bool, extensions=()) -> x509.Certificate:
    now = datetime.datetime.now(datetime.timezone.utc)
    builder = (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject)]))
        .issuer_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, issuer_name)]))
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=30))
        .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True)
    )
    for ext in extensions:
        builder = builder.add_extension(ext, critical=False)
    return builder.sign(issuer_key, hashes.SHA256())


class FakeApple:
    """Plays Apple's attestation CA and one device's Secure Enclave key."""

    def __init__(self, app_id: str = APP_ID) -> None:
        self.root_key = ec.generate_private_key(ec.SECP384R1())
        self.root = _cert("Fake Root", self.root_key, "Fake Root", self.root_key, ca=True)
        self.inter_key = ec.generate_private_key(ec.SECP384R1())
        self.inter = _cert("Fake Intermediate", self.inter_key, "Fake Root", self.root_key, ca=True)
        self.app_id = app_id
        self.device = ec.generate_private_key(ec.SECP256R1())
        point = self.device.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
        self.key_id = hashlib.sha256(point).digest()
        self.counter = 0

    @property
    def root_pem(self) -> bytes:
        return self.root.public_bytes(serialization.Encoding.PEM)

    def attestation(self, challenge: bytes, key_id: bytes | None = None) -> bytes:
        key_id = key_id or self.key_id
        rp = hashlib.sha256(self.app_id.encode()).digest()
        auth = rp + b"\x41" + (0).to_bytes(4, "big") + AAGUID_PRODUCTION + len(key_id).to_bytes(2, "big") + key_id
        nonce = hashlib.sha256(auth + hashlib.sha256(challenge).digest()).digest()
        ext = x509.UnrecognizedExtension(NONCE_OID, NONCE_DER_PREFIX + nonce)
        leaf = _cert("device", self.device, "Fake Intermediate", self.inter_key, ca=False, extensions=[ext])
        return cbor2.dumps({
            "fmt": "apple-appattest",
            "attStmt": {"x5c": [leaf.public_bytes(serialization.Encoding.DER), self.inter.public_bytes(serialization.Encoding.DER)], "receipt": b""},
            "authData": auth,
        })

    def assertion(self, client_data: bytes, counter: int | None = None) -> bytes:
        self.counter = self.counter + 1 if counter is None else counter
        auth = hashlib.sha256(self.app_id.encode()).digest() + b"\x01" + self.counter.to_bytes(4, "big")
        nonce = hashlib.sha256(auth + hashlib.sha256(client_data).digest()).digest()
        return cbor2.dumps({"signature": self.device.sign(nonce, ec.ECDSA(hashes.SHA256())), "authenticatorData": auth})

    def headers(self, method: str, path: str, body: bytes = b"", counter: int | None = None) -> dict:
        client_data = f"{method}\n{path}\n".encode() + body
        return {
            "x-attest-key": base64.b64encode(self.key_id).decode(),
            "x-attest-assertion": base64.b64encode(self.assertion(client_data, counter)).decode(),
            "content-type": "application/json",
        }


class FakeMaia:
    def predict(self, fen: str) -> dict[str, float]:
        return {"e2e4": 0.6, "d2d4": 0.4}


@pytest.fixture
def apple() -> FakeApple:
    return FakeApple()


@pytest.fixture
def client(apple, tmp_path):
    app = public_main.create_public_app(
        settings=public_main.PublicSettings(data_dir=str(tmp_path / "public")),
        verifier=AppAttestVerifier(APP_ID, root_pem=apple.root_pem),
        analysis_engine=FakeAnalysisEngine(), maia_engine=FakeMaia())
    with TestClient(app) as c:
        yield c


def register(client, apple: FakeApple, key_id: bytes | None = None):
    challenge = base64.b64decode(client.post("/v1/attest/challenge").json()["challenge"])
    return client.post("/v1/attest/register", json={
        "key_id": base64.b64encode(key_id or apple.key_id).decode(),
        "attestation": base64.b64encode(apple.attestation(challenge, key_id)).decode(),
        "challenge": base64.b64encode(challenge).decode(),
    })


def post(client, apple, path: str, payload: dict, counter: int | None = None):
    import json

    body = json.dumps(payload).encode()
    return client.post(path, content=body, headers=apple.headers("POST", path, body, counter))


def test_given_genuine_install_when_attested_then_can_analyse_and_ask_maia(client, apple):
    assert register(client, apple).status_code == 200
    r = post(client, apple, "/v1/analysis/jobs", {"job_id": "j1", "game_id": "g", "pgn": PGN, "user_color": "white", "depth": 40})
    assert r.status_code == 200
    for _ in range(100):
        status = client.get("/v1/analysis/jobs/j1", headers=apple.headers("GET", "/v1/analysis/jobs/j1"))
        assert status.status_code == 200
        if status.json()["status"] == "done":
            break
        time.sleep(0.02)
    assert status.json()["status"] == "done"
    assert status.json()["result"]["positions"][0]["lines"][0]["depth"] == public_main.MAX_DEPTH, "depth is capped"
    maia = post(client, apple, "/v1/maia/predict", {"fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"})
    assert maia.json()["policy"]["e2e4"] == 0.6


def test_given_bad_attestations_when_registering_then_rejected(client, apple):
    other_app = FakeApple(app_id="TEAM.com.someone.else")
    other_app.root_key, other_app.root, other_app.inter_key, other_app.inter = apple.root_key, apple.root, apple.inter_key, apple.inter
    assert register(client, other_app).status_code == 401, "certified for a different app"
    assert register(client, FakeApple()).status_code == 401, "chain doesn't lead to the trusted root"
    assert register(client, apple, key_id=hashlib.sha256(b"x").digest()).status_code == 401, "key id must match the certified key"
    challenge = base64.b64decode(client.post("/v1/attest/challenge").json()["challenge"])
    payload = {"key_id": base64.b64encode(apple.key_id).decode(), "attestation": base64.b64encode(apple.attestation(challenge)).decode(),
               "challenge": base64.b64encode(challenge).decode()}
    assert client.post("/v1/attest/register", json=payload).status_code == 200
    assert client.post("/v1/attest/register", json=payload).status_code == 400, "a challenge works once"


def test_given_forged_or_replayed_requests_when_calling_then_401(client, apple):
    job = {"job_id": "j1", "game_id": "g", "pgn": PGN, "user_color": "white"}
    assert post(client, apple, "/v1/analysis/jobs", job).status_code == 401, "not attested yet"
    register(client, apple)
    assert post(client, apple, "/v1/analysis/jobs", job, counter=5).status_code == 200
    assert post(client, apple, "/v1/analysis/jobs", job, counter=5).status_code == 401, "replayed counter"
    import json

    body = json.dumps(job).encode()
    headers = apple.headers("POST", "/v1/analysis/jobs", body)
    tampered = json.dumps({**job, "depth": 60}).encode()
    assert client.post("/v1/analysis/jobs", content=tampered, headers=headers).status_code == 401, "body is signed"
    assert client.get("/v1/analysis/jobs/j1").status_code == 401, "no headers"


def test_given_two_devices_when_reading_jobs_then_each_sees_only_its_own(client, apple):
    register(client, apple)
    post(client, apple, "/v1/analysis/jobs", {"job_id": "mine", "game_id": "g", "pgn": PGN, "user_color": "white"})
    other = FakeApple()
    other.root_key, other.root, other.inter_key, other.inter = apple.root_key, apple.root, apple.inter_key, apple.inter
    register(client, other)
    assert client.get("/v1/analysis/jobs/mine", headers=other.headers("GET", "/v1/analysis/jobs/mine")).status_code == 404


def test_given_oversized_or_junk_input_when_submitting_then_refused(client, apple):
    register(client, apple)
    huge = post(client, apple, "/v1/analysis/jobs", {"job_id": "j", "game_id": "g", "pgn": "1. e4 " * 5000, "user_color": "white"})
    assert huge.status_code == 422
    empty = post(client, apple, "/v1/analysis/jobs", {"job_id": "j", "game_id": "g", "pgn": "not chess", "user_color": "white"})
    assert empty.status_code == 400
    assert post(client, apple, "/v1/maia/predict", {"fen": "garbage"}).status_code == 400


def test_given_flood_when_asking_challenges_then_rate_limited(client):
    codes = [client.post("/v1/attest/challenge", headers={"cf-connecting-ip": "203.0.113.7"}).status_code for _ in range(25)]
    assert codes[:20] == [200] * 20 and codes[-1] == 429
    assert client.post("/v1/attest/challenge", headers={"cf-connecting-ip": "203.0.113.8"}).status_code == 200, "per caller"


def test_given_private_endpoints_when_probed_then_they_do_not_exist(client):
    for path in ["/key", "/health", "/analysis/jobs", "/docs", "/openapi.json", "/redoc", "/maia/predict"]:
        assert client.get(path).status_code == 404, path
    assert client.get("/v1/health").json() == {"ok": True}


def test_public_code_never_touches_the_secrets():
    imports = [
        line for p in Path(public_main.__file__).parent.glob("*.py") for line in p.read_text().splitlines()
        if line.startswith(("import ", "from "))
    ]
    for forbidden in ["secrets_service", "SecretsService", "dpapi", "app.main", "app.security", "anthropic"]:
        assert not any(forbidden in line for line in imports), forbidden
    assert not any("SecretsService" in p.read_text() for p in Path(public_main.__file__).parent.glob("*.py"))


def test_given_huge_or_malformed_requests_when_sent_then_refused_before_reading(client, apple):
    register(client, apple)
    big = b'{"job_id":"j","game_id":"g","user_color":"white","pgn":"' + b"x" * (70 * 1024) + b'"}'
    r = client.post("/v1/analysis/jobs", content=big, headers=apple.headers("POST", "/v1/analysis/jobs", big))
    assert r.status_code == 413
    assert client.post("/v1/attest/challenge", content=b"x", headers={"content-length": "abc"}).status_code in (400, 413)
    bad_id = post(client, apple, "/v1/analysis/jobs", {"job_id": "j", "game_id": "<script>", "pgn": PGN, "user_color": "white"})
    assert bad_id.status_code == 422
    short_key = {"x-attest-key": base64.b64encode(b"short").decode(), "x-attest-assertion": "AA=="}
    assert client.get("/v1/analysis/jobs/j", headers=short_key).status_code == 401
    huge_header = {"x-attest-key": "A" * 5000, "x-attest-assertion": "AA=="}
    assert client.get("/v1/analysis/jobs/j", headers=huge_header).status_code == 400


def test_given_any_response_then_security_headers_are_set(client):
    r = client.get("/v1/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["cache-control"] == "no-store"
    assert r.headers["x-frame-options"] == "DENY"


def test_given_many_finished_jobs_when_pruning_then_oldest_go_first():
    from app.jobs import Job, JobStore

    store = JobStore(FakeAnalysisEngine())
    for i in range(5):
        store._jobs[f"j{i}"] = Job(job_id=f"j{i}", game_id="g", pgn="", user_color="white", depth=1, multipv=1, status="done")
    store._jobs["running"] = Job(job_id="running", game_id="g", pgn="", user_color="white", depth=1, multipv=1, status="running")
    store.prune_finished(keep=3)
    assert list(store._jobs) == ["j3", "j4", "running"]
