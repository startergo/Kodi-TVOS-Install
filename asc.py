#!/usr/bin/env python3
"""
asc.py — tiny App Store Connect API client for renewing the Kodi tvOS signing identity.

No third-party packages: JWTs are signed with /usr/bin/openssl, HTTP goes through /usr/bin/curl.

Config (default ~/.kodi-signing/asc.env, KEY=VALUE lines, $HOME expanded):
    ASC_KEY_ID      Key ID of an App Store Connect *team* API key with the Admin role
    ASC_ISSUER_ID   Issuer ID shown on the API keys page
    ASC_KEY_FILE    path to the AuthKey_<KEYID>.p8 file
    KODI_BUNDLE_ID  bundle ID Kodi is signed as (default com.startergo.UTM.kodi)

Commands:
    asc.py check                 read-only: list Distribution certificates, tvOS Ad Hoc profiles, Apple TVs
    asc.py renew [--out DIR]     create a new Apple Distribution certificate (key generated locally and
                                 imported into the login keychain) and a tvOS Ad Hoc profile for the
                                 bundle ID + all enabled Apple TVs; prints the profile path on the last line
"""
import base64, json, os, subprocess, sys, tempfile, time, datetime

API = "https://api.appstoreconnect.apple.com"
SIGN_DIR = os.path.expanduser("~/.kodi-signing")


def load_config(path=os.path.join(SIGN_DIR, "asc.env")):
    cfg = {"KODI_BUNDLE_ID": "com.startergo.UTM.kodi"}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = os.path.expandvars(v.strip().strip('"'))
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_FILE"):
        if not cfg.get(k):
            sys.exit(f"asc.py: {k} missing from {path}")
    return cfg


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_to_raw(sig, n=32):
    # ECDSA DER  SEQUENCE { INTEGER r, INTEGER s }  ->  r||s (JOSE format)
    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 2 + (sig[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert sig[i] == 0x02
        ln = sig[i + 1]
        v = sig[i + 2:i + 2 + ln].lstrip(b"\x00")
        out += v.rjust(n, b"\x00")
        i += 2 + ln
    return out


def token(cfg):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": cfg["ASC_KEY_ID"], "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": cfg["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
                                 "aud": "appstoreconnect-v1"}).encode())
    msg = f"{header}.{payload}".encode()
    der = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", cfg["ASC_KEY_FILE"]],
                         input=msg, capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def call(cfg, method, path, body=None):
    args = ["/usr/bin/curl", "-sS", "-g", "-X", method, API + path,   # -g: [] in filters are not globs
            "-H", "Authorization: Bearer " + token(cfg), "-w", "\n%{http_code}"]
    if body is not None:
        args += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
    r = subprocess.run(args, input=json.dumps(body).encode() if body is not None else None,
                       capture_output=True)
    if r.returncode != 0:   # don't let CalledProcessError echo the bearer token
        sys.exit(f"asc.py: curl failed ({r.returncode}) on {method} {path}: {r.stderr.decode().strip()}")
    text, _, code = r.stdout.decode().rpartition("\n")
    data = json.loads(text) if text.strip() else {}
    if not code.startswith("2"):
        errs = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in data.get("errors", []))
        sys.exit(f"asc.py: {method} {path} -> HTTP {code}: {errs or text[:300]}")
    return data


def bundle_id(cfg):
    ident = cfg["KODI_BUNDLE_ID"]
    data = call(cfg, "GET", f"/v1/bundleIds?filter[identifier]={ident}&limit=200")["data"]
    match = [b for b in data if b["attributes"]["identifier"] == ident]   # filter is a prefix match
    if not match:
        sys.exit(f"asc.py: App ID {ident} not found on the developer account")
    return match[0]["id"]


def apple_tvs(cfg):
    data = call(cfg, "GET", "/v1/devices?filter[status]=ENABLED&limit=200")["data"]
    return [d for d in data if d["attributes"].get("deviceClass") == "APPLE_TV"]


def check(cfg):
    certs = call(cfg, "GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200")["data"]
    print("Apple Distribution certificates:")
    for c in certs:
        a = c["attributes"]
        print(f"  {c['id']}  {a.get('name')}  expires {a.get('expirationDate', '')[:10]}")
    profs = call(cfg, "GET", "/v1/profiles?filter[profileType]=TVOS_APP_ADHOC&limit=200")["data"]
    print("tvOS Ad Hoc profiles:")
    for p in profs:
        a = p["attributes"]
        print(f"  {a.get('name')}  {a.get('profileState')}  expires {a.get('expirationDate', '')[:10]}")
    print(f"App ID {cfg['KODI_BUNDLE_ID']}: {bundle_id(cfg)}")
    print("Apple TVs:", ", ".join(f"{d['attributes']['name']} ({d['attributes']['udid']})" for d in apple_tvs(cfg)) or "none")


def renew(cfg, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    stamp = datetime.date.today().isoformat()
    key = os.path.join(SIGN_DIR, f"dist-{stamp}.key")
    csr = os.path.join(SIGN_DIR, f"dist-{stamp}.certSigningRequest")
    cer = os.path.join(SIGN_DIR, f"distribution-{stamp}.cer")

    print("Generating private key and CSR locally...")
    subprocess.run(["/usr/bin/openssl", "genrsa", "-out", key, "2048"], check=True, capture_output=True)
    os.chmod(key, 0o600)
    subprocess.run(["/usr/bin/openssl", "req", "-new", "-key", key, "-out", csr,
                    "-subj", "/CN=Kodi tvOS signing/C=US"], check=True)

    print("Creating Apple Distribution certificate...")
    body = {"data": {"type": "certificates",
                     "attributes": {"certificateType": "DISTRIBUTION", "csrContent": open(csr).read()}}}
    cert = call(cfg, "POST", "/v1/certificates", body)["data"]
    with open(cer, "wb") as f:
        f.write(base64.b64decode(cert["attributes"]["certificateContent"]))
    print(f"  {cert['attributes'].get('name')}  expires {cert['attributes'].get('expirationDate', '')[:10]}")

    kc = os.path.expanduser("~/Library/Keychains/login.keychain-db")
    subprocess.run(["security", "import", key, "-k", kc, "-T", "/usr/bin/codesign"], check=True)
    subprocess.run(["security", "import", cer, "-k", kc], check=True)

    tvs = apple_tvs(cfg)
    if not tvs:
        sys.exit("asc.py: no enabled Apple TV registered on the account")
    name = f"Kodi tvOS AdHoc {stamp}"
    print(f"Creating profile '{name}' for {', '.join(d['attributes']['name'] for d in tvs)}...")
    body = {"data": {"type": "profiles",
                     "attributes": {"name": name, "profileType": "TVOS_APP_ADHOC"},
                     "relationships": {
                         "bundleId": {"data": {"type": "bundleIds", "id": bundle_id(cfg)}},
                         "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
                         "devices": {"data": [{"type": "devices", "id": d["id"]} for d in tvs]}}}}
    prof = call(cfg, "POST", "/v1/profiles", body)["data"]
    path = os.path.join(out_dir, name.replace(" ", "_") + ".mobileprovision")
    with open(path, "wb") as f:
        f.write(base64.b64decode(prof["attributes"]["profileContent"]))
    print(f"  expires {prof['attributes'].get('expirationDate', '')[:10]}")
    print(path)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    cfg = load_config()
    if cmd == "check":
        check(cfg)
    elif cmd == "renew":
        out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else os.path.expanduser("~/Downloads")
        renew(cfg, out)
    else:
        sys.exit(__doc__)
