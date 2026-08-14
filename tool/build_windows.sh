#!/usr/bin/env bash
# WSL에서 Windows Flutter로 Windows 데스크톱 앱을 빌드하는 헬퍼.
#
# 배경: flutter build windows는 Windows 플러그인 심링크(.plugin_symlinks)를
# 생성하는데 \\wsl.localhost UNC 파일시스템에서는 실패한다. 이 스크립트는
# 예제 앱을 Windows 로컬 디스크(NTFS)로 robocopy해 빌드하고, 결과 EXE를
# 워크스페이스로 복사해 온다. (tool/build_android.sh와 같은 패턴)
#
# 사용법:
#   tool/build_windows.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-release}"
case "$MODE" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]"; exit 1 ;;
esac

WIN_BUILD_ROOT='C:\Users\mathe\.tikitaka_build'
WIN_PROJECT="$WIN_BUILD_ROOT\\tikitaka_lfm"
WIN_EXAMPLE="$WIN_PROJECT\\example"
UNC_SRC='\\wsl.localhost\Ubuntu\home\saint\tikitaka_lfm'
FLUTTER_BAT='C:\Users\mathe\flutter\bin\flutter.bat'

echo "== 1/4 프로젝트를 Windows 빌드 디렉토리로 복사 (robocopy) =="
# robocopy: 캐시/빌드 산출물 제외, 성공 시 exit 1(복사됨) 허용
cmd.exe /c "robocopy $UNC_SRC $WIN_PROJECT /E /XD .git .dart_tool build .gradle ephemeral /NFL /NDL /NJH /NJS /NP" || true

echo "== 2/4 pub get =="
cmd.exe /c "pushd $WIN_EXAMPLE && $FLUTTER_BAT pub get" >/dev/null

echo "== 3/4 flutter build windows --$MODE =="
cmd.exe /c "pushd $WIN_EXAMPLE && $FLUTTER_BAT build windows --$MODE" | tail -15

echo "== 4/4 실행 폴더(EXE + data)를 워크스페이스로 복사 =="
EXE_DIR="/mnt/c/Users/mathe/.tikitaka_build/tikitaka_lfm/example/build/windows/x64/runner/$MODE"
if compgen -G "$EXE_DIR/*.exe" >/dev/null; then
  DEST="build/windows/$MODE"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cp -r "$EXE_DIR"/. "$DEST/"
  echo "OK: $PWD/$DEST/"
  ls -la "$DEST"
else
  echo "FAIL: EXE를 찾지 못했습니다: $EXE_DIR"
  exit 1
fi
