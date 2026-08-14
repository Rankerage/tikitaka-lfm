#!/usr/bin/env bash
# WSL에서 Windows Flutter로 Android APK를 안정적으로 빌드하는 헬퍼.
#
# 배경: Windows Gradle은 \\wsl.localhost UNC 파일시스템에서 mmap(FileHasher)이
# 실패해 WSL 경로에서 직접 빌드하지 못한다(IOException: 잘못된 기능입니다).
# 이 스크립트는 예제 앱을 Windows 로컬 디스크(NTFS)로 robocopy로 복사해
# 빌드하고, 결과 APK를 워크스페이스로 복사해 온다.
#
# 사용법:
#   tool/build_android.sh [debug|release|bundle]
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-debug}"
case "$MODE" in
  debug|release|bundle) ;;
  *) echo "usage: $0 [debug|release|bundle]"; exit 1 ;;
esac

# 모드 → flutter build 인자 매핑
if [[ "$MODE" == "bundle" ]]; then
  BUILD_TARGET='appbundle'
  EXTRA='--release'
else
  BUILD_TARGET='apk'
  EXTRA="--$MODE"
fi

WIN_BUILD_ROOT='C:\Users\mathe\.tikitaka_build'
WIN_PROJECT="$WIN_BUILD_ROOT\\tikitaka_lfm"
WIN_EXAMPLE="$WIN_PROJECT\\example"
UNC_SRC='\\wsl.localhost\Ubuntu\home\saint\tikitaka_lfm'
FLUTTER_BAT='C:\Users\mathe\flutter\bin\flutter.bat'

echo "== 1/4 프로젝트를 Windows 빌드 디렉토리로 복사 (robocopy) =="
# robocopy: 캐시/빌드 산출물 제외, 성공 시 exit 1(복사됨) 허용
# (example의 `path: ../` 의존성을 위해 루트 패키지까지 함께 복사)
cmd.exe /c "robocopy $UNC_SRC $WIN_PROJECT /E /XD .git .dart_tool build .gradle ephemeral /NFL /NDL /NJH /NJS /NP" || true

echo "== 2/4 pub get =="
cmd.exe /c "pushd $WIN_EXAMPLE && $FLUTTER_BAT pub get" >/dev/null

echo "== 3/4 flutter build ${BUILD_TARGET:-apk} =="
cmd.exe /c "pushd $WIN_EXAMPLE && $FLUTTER_BAT build ${BUILD_TARGET:-apk} $EXTRA" | tail -20

echo "== 4/4 산출물을 워크스페이스로 복사 =="
if [[ "$MODE" == "bundle" ]]; then
  APK_SRC="/mnt/c/Users/mathe/.tikitaka_build/tikitaka_lfm/example/build/app/outputs/bundle/release/app-release.aab"
  DEST="build/aab"
else
  APK_SRC="/mnt/c/Users/mathe/.tikitaka_build/tikitaka_lfm/example/build/app/outputs/flutter-apk/app-${MODE}.apk"
  DEST="build/apk"
fi
if [[ -f "$APK_SRC" ]]; then
  mkdir -p "$DEST"
  cp "$APK_SRC" "$DEST/"
  echo "OK: $PWD/$DEST/$(basename "$APK_SRC")"
else
  echo "FAIL: 산출물을 찾지 못했습니다: $APK_SRC"
  exit 1
fi
