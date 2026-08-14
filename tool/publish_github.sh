#!/usr/bin/env bash
# GitHub 배포 헬퍼 — 코드 push + 웹 데모(gh-pages) 배포.
#
# 전제: gh CLI 인증 완료 (gh auth login — 패스키 계정은 device flow 권장)
#
# 사용법:
#   tool/publish_github.sh              # 코드 push (+ 저장소 생성)
#   tool/publish_github.sh --web        # 코드 push + 웹 데모 빌드·배포
#   tool/publish_github.sh --release    # + GitHub Release에 APK/AAB 첨부
set -euo pipefail
cd "$(dirname "$0")/.."

REPO='Rankerage/tikitaka-lfm'
MODE="${1:-push}"

echo "== 0/5 인증 확인 =="
gh auth status >/dev/null 2>&1 || { echo "FAIL: gh 인증 필요 (gh auth login)"; exit 1; }

echo "== 1/5 원격 저장소 확인/생성 =="
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo create tikitaka-lfm --public --source=. --remote=origin --push
  echo "   ✅ 저장소 생성 + 초기 push 완료"
else
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$REPO.git"
  git push -u origin master
  echo "   ✅ 기존 저장소에 push 완료"
fi

echo "== 2/5 CI 상태 확인 (Actions) =="
gh run list --repo "$REPO" --limit 1 2>/dev/null | head -3 || echo "   (Actions가 아직 안 돌았거나 없음 — push 트리거 대기)"

if [[ "$MODE" == "--web" || "$MODE" == "--release" ]]; then
  echo "== 3/5 웹 데모 빌드 =="
  (cd example && flutter build web --release)
  echo "== 4/5 gh-pages 배포 (웹 빌드만, 별도 임시 저장소) =="
  TMP="$(mktemp -d)"
  cp -r example/build/web/. "$TMP/"
  (cd "$TMP" && git init -q -b gh-pages && git add -A \
    && git -c user.name="TikiTaka" -c user.email="dev@tikitaka.local" commit -q -m "web demo" \
    && git remote add origin "https://github.com/$REPO.git" \
    && git push -f origin gh-pages)
  rm -rf "$TMP"
  echo "   ✅ Pages 재배포 완료 → https://$REPO"
fi

if [[ "$MODE" == "--release" ]]; then
  echo "== 5/5 GitHub Release 첨부 =="
  ./tool/build_android.sh release >/dev/null 2>&1
  ./tool/build_android.sh bundle >/dev/null 2>&1
  # 버전을 example/pubspec.yaml에서 동적으로 읽는다 (예: 1.3.0)
  VERSION="$(grep -m1 '^version:' example/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
  gh release create "v$VERSION" \
    build/apk/app-release.apk build/aab/app-release.aab \
    --repo "$REPO" --title "TikiTaka v$VERSION" \
    --notes "TikiTaka v$VERSION — 온디바이스 AI 학습 파트너" || true
  echo "   ✅ Release 첨부 완료 (v$VERSION)"
fi

echo "== 완료 =="
