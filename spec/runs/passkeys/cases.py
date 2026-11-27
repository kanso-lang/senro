"""Writes cases.txt for spec/runs/passkeys: what a browser sends after an
authenticator registers a passkey or signs in with one, made here with a
real P-256 key from Python's `cryptography`, and the same with one thing
wrong. Each line is

    label|kind|client data|attestation or authenticator data|signature|count

in hex, kind `create` or `get`; a `get` line is checked against the
credential the first `create` line registers, holding the stored count. The
keys come from fixed secrets, but ECDSA signatures are random, so a rerun
writes different signatures that check the same. Run from this directory:
python3 cases.py"""
import hashlib
import json
import struct

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec

RP = "example.test"
ORIGIN = "https://example.test"
CHALLENGE = "c2Vucm8tc3BlYy1jaGFsbGVuZ2UtMzItYnl0ZXMhIQ"
CRED_ID = bytes(range(1, 17))

key = ec.derive_private_key(0x1D1E1F, ec.SECP256R1())
other = ec.derive_private_key(0x2E2F30, ec.SECP256R1())


def cbor(v):
    def head(major, n):
        if n < 24:
            return bytes([major << 5 | n])
        if n < 256:
            return bytes([major << 5 | 24, n])
        if n < 65536:
            return bytes([major << 5 | 25]) + struct.pack(">H", n)
        return bytes([major << 5 | 26]) + struct.pack(">I", n)
    if isinstance(v, bool):
        return bytes([0xF5 if v else 0xF4])
    if isinstance(v, int):
        return head(0, v) if v >= 0 else head(1, -1 - v)
    if isinstance(v, bytes):
        return head(2, len(v)) + v
    if isinstance(v, str):
        b = v.encode()
        return head(3, len(b)) + b
    if isinstance(v, list):
        return head(4, len(v)) + b"".join(cbor(x) for x in v)
    if isinstance(v, dict):
        return head(5, len(v)) + b"".join(cbor(k) + cbor(x) for k, x in v.items())
    raise TypeError(v)


def cose(k, alg=-7):
    n = k.public_key().public_numbers()
    return cbor({1: 2, 3: alg, -1: 1, -2: n.x.to_bytes(32, "big"), -3: n.y.to_bytes(32, "big")})


def client(kind, challenge=CHALLENGE, origin=ORIGIN):
    return json.dumps({"type": kind, "challenge": challenge, "origin": origin,
                       "crossOrigin": False}, separators=(",", ":")).encode()


def auth(count, flags=0x05, rp=RP, made=None):
    data = hashlib.sha256(rp.encode()).digest() + bytes([flags]) + struct.pack(">I", count)
    if made is not None:
        data += bytes(16) + struct.pack(">H", len(CRED_ID)) + CRED_ID + made
    return data


def attestation(data):
    return cbor({"fmt": "none", "attStmt": {}, "authData": data})


def signed(k, data, client_bytes):
    return k.sign(data + hashlib.sha256(client_bytes).digest(), ec.ECDSA(hashes.SHA256()))


lines = []


def create(label, c, a):
    lines.append([label, "create", c.hex(), a.hex(), "", "0"])


def get(label, c, data, sig, stored):
    lines.append([label, "get", c.hex(), data.hex(), sig.hex(), str(stored)])


made = cose(key)
create("a passkey is made", client("webauthn.create"), attestation(auth(0, 0x45, made=made)))
create("for a sign-in", client("webauthn.get"), attestation(auth(0, 0x45, made=made)))
create("another challenge", client("webauthn.create", challenge="b3RoZXI"),
       attestation(auth(0, 0x45, made=made)))
create("another origin", client("webauthn.create", origin="https://evil.test"),
       attestation(auth(0, 0x45, made=made)))
create("another site's id", client("webauthn.create"),
       attestation(auth(0, 0x45, rp="evil.test", made=made)))
create("nobody present", client("webauthn.create"), attestation(auth(0, 0x44, made=made)))
create("no user verified", client("webauthn.create"), attestation(auth(0, 0x41, made=made)))
create("no credential", client("webauthn.create"), attestation(auth(0, 0x05)))
create("an RSA key", client("webauthn.create"), attestation(auth(0, 0x45, made=cose(key, -257))))
create("not CBOR", client("webauthn.create"), attestation(auth(0, 0x45, made=made))[:-5])
create("not JSON", b"{\"type\":", attestation(auth(0, 0x45, made=made)))

c = client("webauthn.get")
good = auth(5)
get("a sign-in", c, good, signed(key, good, c), 2)
get("the data changed after", c, auth(6), signed(key, good, c), 2)
get("another key signed", c, good, signed(other, good, c), 2)
get("the count went back", c, auth(3), signed(key, auth(3), c), 5)
get("the same count again", c, good, signed(key, good, c), 5)
zero = auth(0)
get("a key that does not count", c, zero, signed(key, zero, c), 0)
spaced = c[:-1] + b" }"
get("the client data changed after", spaced, good, signed(key, good, c), 2)
other_challenge = client("webauthn.get", challenge="b3RoZXI")
get("another challenge", other_challenge, good, signed(key, good, other_challenge), 2)
unverified = auth(5, 0x01)
get("no user verified", c, unverified, signed(key, unverified, c), 2)
get("a signature that is not DER", c, good, b"\x30\x02\x02\x00", 2)

with open("cases.txt", "w") as f:
    for line in lines:
        f.write("|".join(line) + "\n")
