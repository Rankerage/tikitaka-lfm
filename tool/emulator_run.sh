#!/usr/bin/env bash
# Android 에뮬레이터에서 티키타카 릴리스 APK를 설치·실행·검증하는 헬퍼.
#
# 전제: Android SDK에 emulator 패키지 + 시스템 이미지 설치, AVD 'tikitaka' 생성
#   (sdkmanager로 emulator/system-images;android-36;google_apis;x86_64 설치 후
#    avdmanager create avd -n tikitaka -k system-images;android-36;google_apis;x86_64 -d pixel_5)
#
# 사용법:
#   tool/emulator_run.sh            # 빌드(선택) + 부팅 + 설치 + 실행 + 검증
set -euo pipefail
cd "$(dirname "$0")/.."

SDK='C:\Users\mathe\Android'
ADB="$SDK\\platform-tools\\adb.exe"
EMU="$SDK\\emulator\\emulator.exe"

echo "== 1/5 에뮬레이터 부팅 (헤드리스) =="
if ! cmd.exe /c "$ADB devices" | grep -q "emulator-5554"; then
  cmd.exe /c "start /b $EMU -avd tikitaka -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect > NUL 2>&1"
fi
echo "   부팅 대기 중..."
for i in $(seq 1 60); do
  BOOT=$(cmd.exe /c "$ADB shell getprop sys.boot_completed 2>nul" 2>/dev/null | tr -d '\r')
  [ "$BOOT" = "1" ] && echo "   ✅ 부팅 완료 (~$((i*5))s)" && break
  sleep 5
done
[ "$BOOT" != "1" ] && echo "FAIL: 에뮬레이터 부팅 실패" && exit 1

echo "== 2/5 릴리스 APK 설치 =="
cmd.exe /c "$ADB install -r \\\\wsl.localhost\\Ubuntu\\home\\saint\\tikitaka_lfm\\build\\apk\\app-release.apk" | tail -1

echo "== 3/5 앱 실행 =="
cmd.exe /c "$ADB shell am start -n com.tikitaka.tikitaka_example/.MainActivity" | tail -1
sleep 8

echo "== 4/5 프로세스 확인 =="
PID=$(cmd.exe /c "$ADB shell pidof com.tikitaka.tikitaka_example" 2>/dev/null | tr -d '\r')
[ -z "$PID" ] && echo "FAIL: 앱 프로세스 없음" && exit 1
echo "   ✅ PID $PID"

echo "== 5/5 크래시 확인 =="
if cmd.exe /c "$ADB logcat -d -t 800 2>nul" | grep -i "FATAL EXCEPTION" | grep -q tikitaka; then
  echo "FAIL: FATAL 크래시 발견"
  exit 1
fi
echo "   ✅ FATAL 없음 — 앱 정상 구동"
