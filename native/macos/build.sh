#!/bin/bash
#
# camsink 가상 카메라를 빌드·서명·공증하고 /Applications 에 설치한다.
#
# macOS 13 부터 가상 카메라는 서명된 앱에 내장된 시스템 익스텐션이어야 한다.
# SIP 가 켜져 있으면 개발용 서명으로는 로드되지 않으므로(개발자 모드가 SIP
# 해제를 요구한다) Developer ID 서명과 공증을 거친다.
#
# 필요한 것:
#   - Apple Developer Program 계정과 Developer ID Application 인증서
#   - App Store Connect API 키 (공증용)
#   - scripts/provision.py 로 만든 프로비저닝 프로파일
#
# 설정은 저장소 최상위의 .env 또는 환경변수로 준다. .env.example 참고.
#
set -euo pipefail

cd "$(dirname "$0")/../.."
if [ -f .env ]; then set -a; . ./.env; set +a; fi

: "${TEAM_ID:?TEAM_ID 가 필요합니다. .env.example 을 참고하세요.}"
: "${ASC_KEY_ID:?ASC_KEY_ID 가 필요합니다.}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID 가 필요합니다.}"
BUNDLE_ID="${BUNDLE_ID:-com.lunartown.camsink}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
APP_PROFILE="${APP_PROFILE:-camsink app devid}"
EXT_PROFILE="${EXT_PROFILE:-camsink ext devid}"

cd native/macos
BUILD_DIR="$PWD/build"
APP_NAME="CamsinkApp.app"

step() { echo; echo "==> $1"; }

if [ ! -f "$ASC_KEY_PATH" ]; then
    echo "API 키를 찾을 수 없습니다: $ASC_KEY_PATH" >&2
    exit 1
fi

step "이전 빌드 정리"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

step "archive"
xcodebuild -project camsink.xcodeproj -scheme CamsinkApp -configuration Release \
    -archivePath "$BUILD_DIR/camsink.xcarchive" archive \
    | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

step "export (Developer ID)"
cat > "$BUILD_DIR/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>manual</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_ID}</key><string>${APP_PROFILE}</string>
        <key>${BUNDLE_ID}.extension</key><string>${EXT_PROFILE}</string>
    </dict>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$BUILD_DIR/camsink.xcarchive" \
    -exportPath "$BUILD_DIR/export" -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
    | grep -E "error:|EXPORT (SUCCEEDED|FAILED)"

APP="$BUILD_DIR/export/$APP_NAME"

step "공증 제출 (몇 분 걸립니다)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/camsink.zip"
xcrun notarytool submit "$BUILD_DIR/camsink.zip" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait | tail -3

step "티켓 첨부"
xcrun stapler staple "$APP"

step "Gatekeeper 확인"
spctl -a -vvv -t exec "$APP" 2>&1 | head -3

step "/Applications 설치"
# 실행 중이면 교체가 실패하므로 먼저 종료한다.
osascript -e 'quit app "CamsinkApp"' 2>/dev/null || true
rm -rf "/Applications/$APP_NAME"
cp -R "$APP" /Applications/

echo
echo "설치 완료: /Applications/$APP_NAME"
echo "앱을 열어 '설치'를 누르고, 시스템 설정 > 일반 > 로그인 항목 및 확장 >"
echo "카메라 확장 프로그램에서 camsink 을 켜주세요."
