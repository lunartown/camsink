#!/usr/bin/env python3
"""Apple 개발자 계정에 camsink 빌드에 필요한 것들을 만들어 둔다.

Xcode 의 자동 서명은 여기서 쓸 수 없다. 시스템 익스텐션은 Developer ID
서명이 필요한데, exportArchive 의 자동 서명은 클라우드 서명 권한 오류를 낸다.
그래서 App Store Connect API 로 직접 만든다.

    pip install pyjwt cryptography requests
    python scripts/provision.py

하는 일:
  1. 이 맥을 기기로 등록 (없으면)
  2. App ID 두 개 생성 (앱, 익스텐션)
  3. capability 부여 - SYSTEM_EXTENSION_INSTALL, APP_GROUPS
  4. Developer ID 프로비저닝 프로파일 생성 후 설치

순서가 중요하다. capability 를 부여하기 전에 만든 프로파일에는 해당
엔타이틀먼트가 들어가지 않는다.
"""

import base64
import os
import re
import subprocess
import sys
import time
from pathlib import Path

try:
    import jwt
    import requests
except ImportError:
    sys.exit("pip install pyjwt cryptography requests 가 필요합니다.")

BASE = "https://api.appstoreconnect.apple.com/v1"
PROFILE_DIR = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"


def load_env():
    """저장소 최상위의 .env 를 읽어 환경변수에 넣는다."""
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip().strip('"\''))


load_env()

TEAM_ID = os.environ.get("TEAM_ID")
KEY_ID = os.environ.get("ASC_KEY_ID")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID")
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.lunartown.camsink")
KEY_PATH = Path(os.environ.get(
    "ASC_KEY_PATH", Path.home() / f".appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"))

if not all([TEAM_ID, KEY_ID, ISSUER_ID]):
    sys.exit("TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID 가 필요합니다. .env.example 참고.")


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(), algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"})


def call(method, path, body=None, params=None):
    r = requests.request(
        method, f"{BASE}{path}",
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"},
        json=body, params=params, timeout=30)
    data = {}
    if r.text:
        try:
            data = r.json()
        except ValueError:
            data = {"raw": r.text}
    if r.status_code >= 400:
        for err in data.get("errors", [{"detail": str(data)}]):
            print(f"    ! {err.get('title', '')}: {err.get('detail', '')}")
    return r.status_code, data


def provisioning_udid():
    out = subprocess.run(["system_profiler", "SPHardwareDataType"],
                         capture_output=True, text=True).stdout
    match = re.search(r"Provisioning UDID:\s*(\S+)", out)
    return match.group(1) if match else None


def ensure_device():
    udid = provisioning_udid()
    if not udid:
        print("  이 맥의 Provisioning UDID 를 읽지 못했습니다. 건너뜁니다.")
        return
    _, data = call("GET", "/devices", params={"limit": 200})
    for item in data.get("data", []):
        if item["attributes"]["udid"] == udid:
            print(f"  기기 이미 등록됨 ({udid})")
            return
    status, _ = call("POST", "/devices", {
        "data": {"type": "devices", "attributes": {
            "name": "camsink build machine", "platform": "MAC_OS", "udid": udid}}})
    print(f"  기기 등록: HTTP {status}")


def ensure_bundle_id(identifier, name):
    _, data = call("GET", "/bundleIds",
                   params={"filter[identifier]": identifier, "limit": 10})
    for item in data.get("data", []):
        if item["attributes"]["identifier"] == identifier:
            print(f"  이미 있음: {identifier}")
            return item["id"]
    status, data = call("POST", "/bundleIds", {
        "data": {"type": "bundleIds", "attributes": {
            "identifier": identifier, "name": name, "platform": "MAC_OS"}}})
    if status != 201:
        sys.exit(f"Bundle ID 생성 실패: {identifier}")
    print(f"  생성: {identifier}")
    return data["data"]["id"]


def enable_capability(bundle_ref, capability):
    status, _ = call("POST", "/bundleIdCapabilities", {
        "data": {"type": "bundleIdCapabilities",
                 "attributes": {"capabilityType": capability},
                 "relationships": {"bundleId": {
                     "data": {"type": "bundleIds", "id": bundle_ref}}}}})
    # 이미 켜져 있으면 409 가 나는데 그건 문제가 아니다.
    print(f"  {capability}: {'OK' if status in (201, 409) else f'HTTP {status}'}")


def developer_id_cert():
    _, data = call("GET", "/certificates", params={"limit": 200})
    for item in data.get("data", []):
        if item["attributes"]["certificateType"] == "DEVELOPER_ID_APPLICATION":
            print(f"  인증서: {item['attributes']['name']}")
            return item["id"]
    sys.exit("Developer ID Application 인증서가 없습니다. Xcode 에서 먼저 만드세요.")


def create_profile(name, bundle_ref, cert_id):
    # 같은 이름이 있으면 지운다. capability 를 나중에 켠 경우 옛 프로파일에는
    # 엔타이틀먼트가 빠져 있기 때문이다.
    _, data = call("GET", "/profiles", params={"limit": 200})
    for item in data.get("data", []):
        if item["attributes"]["name"] == name:
            call("DELETE", f"/profiles/{item['id']}")

    status, data = call("POST", "/profiles", {
        "data": {"type": "profiles",
                 "attributes": {"name": name, "profileType": "MAC_APP_DIRECT"},
                 "relationships": {
                     "bundleId": {"data": {"type": "bundleIds", "id": bundle_ref}},
                     "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})
    if status != 201:
        sys.exit(f"프로파일 생성 실패: {name}")
    attrs = data["data"]["attributes"]
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    path = PROFILE_DIR / f"{attrs['uuid']}.provisionprofile"
    path.write_bytes(base64.b64decode(attrs["profileContent"]))
    print(f"  프로파일: {name} -> {path.name}")


def main():
    print("[1] 기기 등록")
    ensure_device()

    print("[2] App ID")
    app_ref = ensure_bundle_id(BUNDLE_ID, "camsink")
    ext_ref = ensure_bundle_id(f"{BUNDLE_ID}.extension", "camsink extension")

    print("[3] capability (프로파일 생성 전에 해야 한다)")
    enable_capability(app_ref, "SYSTEM_EXTENSION_INSTALL")
    enable_capability(app_ref, "APP_GROUPS")
    enable_capability(ext_ref, "APP_GROUPS")

    print("[4] 프로파일")
    cert = developer_id_cert()
    create_profile(os.environ.get("APP_PROFILE", "camsink app devid"), app_ref, cert)
    create_profile(os.environ.get("EXT_PROFILE", "camsink ext devid"), ext_ref, cert)

    print("\n준비됐습니다. native/macos/build.sh 를 실행하세요.")


if __name__ == "__main__":
    main()
