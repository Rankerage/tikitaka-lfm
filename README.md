# 🎯 TikiTaka LFM2.5 엔진

**능동적 학습 파트너** — AI가 먼저 말 걸고, 학습을 시키는 온디바이스 엔진.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Rankerage/tikitaka-lfm)](https://github.com/Rankerage/tikitaka-lfm/releases)
[![Web Demo](https://img.shields.io/badge/demo-web%20(gh--pages)-teal)](https://rankerage.github.io/tikitaka-lfm/)
[![CI](https://img.shields.io/github/actions/workflow/status/Rankerage/tikitaka-lfm/ci.yml?branch=main&label=CI)](https://github.com/Rankerage/tikitaka-lfm/actions)

## 설치 (패키지로 사용)
```bash
# Ollama + LFM2.5 (PC 또는 폰에)
curl -fsSL https://ollama.com/install.sh | sh
ollama pull lfm2.5-thinking:1.2b

# Flutter 프로젝트에 추가
flutter pub add tikitaka_lfm --path ../tikitaka_lfm
```

## 사용법
```dart
final engine = TikiTakaLfm();
await engine.setSubject('수학');
final reply = await engine.ask('이차방정식 어려워요');
// or
TikiTakaChat(engine: engine, subject: '수학');

// 스트리밍 답변 (토큰 단위로 표시)
await for (final delta in engine.askStream('이차방정식 어려워요')) {
  print(delta); // 답변이 조각조각 내려온다
}

// 답변 평가 — 히스토리에 남기지 않는 1회성 평가
final feedback = await engine.gradeDirect('x = 2입니다');

// 학습 통계 (연속 학습 streak)
final stats = engine.stats; // totalQuestions, streakDays, bestStreak, lastActive

// 최근 7일 일별 활동 (오늘 포함, 활동 없는 날은 0)
final weekly = engine.weeklyActivity; // {'yyyy-MM-dd': 질문 수, ...}

// 모든 과목의 통계 (과목 → TkStats)
final all = await engine.allStats();

// 학습 기록을 마크다운으로 내보내기 (Obsidian 노트용)
final notes = engine.exportHistory();

// 최근 대화를 AI로 요약 (히스토리에 기록하지 않음)
final summary = await engine.summarize(maxLines: 3);

// 주제별 맞춤 학습 계획 (최근 대화·통계 반영)
final plan = await engine.learningPlan(minutes: 10);

// 오답노트 복습 (플래시카드)
engine.addMistake('문제', '답', note: '메모');
final review = engine.nextMistakeReview(); // 순환 순서, 없으면 null

// 과목 데이터 전체 삭제 (기록·오답노트·통계)
await engine.deleteSubject('수학');

// 조교 메시지(퀴즈 등)를 모델 호출 없이 히스토리에 기록
engine.tutorSay(engine.makeQuiz());

// 앱 종료 전 대기 중인 기록 저장 확정 (선택)
await engine.flush();
```

> `TikiTakaChat(showActions: true)`를 쓰면 '문제/평가' 빠른 액션 버튼이
> 입력창 위에 표시된다 (문제: `makeQuiz`+`tutorSay`, 평가: `gradeDirect`).

## 능동적 학습
- `proactiveGreeting()` — AI가 먼저 인사 + 학습 유도
- `makeQuiz()` — 주제 기반 퀴즈 자동 출제
- `startProactiveLearning(interval, onTick)` — 정기 학습 알림 (onTick으로 push 연동)
- `gradeDirect(answer)` — 평가 요청을 대화 기록에 남기지 않는 1회성 평가
- `flush()` — 디바운스된 기록 저장을 즉시 확정
- `stats` — 학습 통계 (총 질문 수, 연속 학습 streak, 최고 streak, 마지막 활동일)
- **과목별 분리** — `setSubject()`로 주제를 바꾸면 대화 기록·통계가 주제별 키로
  분리 저장된다 (기본 주제는 기존 키 호환)
- 오프라인 완전 동작 (인터넷 불필요)

## 내부 동작
- **컨텍스트 캡**: 모델 요청 시 최근 20개 메시지만 전송
- **기록 상한**: 메모리·저장소 모두 최근 100개 유지 (오래된 기록 자동 제거)
- **저장 디바운스**: 답변마다 쓰지 않고 300ms(기본) 동안 연기 — 연속 대화 중 중복 쓰기 방지
- **연속 학습 streak**: 성공한 대화가 하루 단위로 이어지면 증가, 하루 이상 건너뛰면 리셋
  (최고 기록은 리셋해도 유지)

## 모델
- **LFM2.5-1.2B** (Liquid AI) — 731MB 초경량
- 폰·태블릿·Raspberry Pi 어디서든 실행 가능
- 프라이버시 100% (모든 대화가 기기 안에서)

## 프로젝트 구조
```
lib/
  tikitaka_lfm.dart   # 엔진 (Ollama 연동, 기록, 퀴즈, 능동적 학습)
  tikitaka_chat.dart  # 채팅 위젯
test/
  tikitaka_lfm_test.dart  # 엔진 단위 테스트 (HTTP 모킹)
example/                  # 실행 가능한 예제 앱
  lib/main.dart           # 주제 선택 + Ollama 설정 UI
```

## GitHub 배포
```bash
# 저장소: https://github.com/Rankerage/tikitaka-lfm (public)
# 웹 데모: https://rankerage.github.io/tikitaka-lfm/

# 코드 push + 웹 데모 재배포
tool/publish_github.sh            # 코드 push
tool/publish_github.sh --web      # + 웹 데모(gh-pages) 배포

# CI 워크플로 활성화 (최초 1회, workflow 스코프 필요)
#   gh auth refresh -h github.com -s workflow   ← 기기 코드 입력
#   git add .github/workflows/ci.yml && git commit && git push
```

## 개발
```bash
# 분석 (린트)
flutter analyze

# 테스트
flutter test
flutter test example    # 예제 앱 위젯 테스트

# 예제 앱 실행 (Android 에뮬레이터 등)
cd example && flutter run
```
> 이 리포는 Flutter SDK가 없는 환경에서 개발하므로, Windows 쪽 툴체인이 있는
> WSL에서는 `cmd.exe /c "pushd \\wsl.localhost\Ubuntu\home\saint\tikitaka_lfm && C:\Users\mathe\flutter\bin\flutter.bat <cmd>"` 형태로 실행한다.

### Android APK 빌드 (WSL + Windows Gradle)
Windows Gradle은 `\\wsl.localhost` UNC 파일시스템에서 mmap(FileHasher) 오류로
WSL 경로에서 직접 빌드하지 못한다. `tool/build_android.sh`가 프로젝트를 Windows
로컬 디스크(NTFS)로 복사해 빌드한 뒤 APK를 `build/apk/`로 가져온다:
```bash
tool/build_android.sh debug      # 또는 release
# → build/apk/app-debug.apk

tool/build_android.sh bundle     # Play 스토어용 App Bundle (릴리스 키 서명)
# → build/aab/app-release.aab
```

#### 릴리스 서명
`example/android/key.properties` + `app/tikitaka-release.jks`(둘 다 git 제외)가
있으면 release APK가 그 키로 서명된다 (없으면 디버그 키로 폴백).
키는 Play 스토어 업로드에 그대로 쓰이므로 백업을 잘 보관할 것:
```bash
keytool -printcert -jarfile build/apk/app-release.apk   # v1 한정
# 또는
apksigner verify --print-certs build/apk/app-release.apk # v2/v3 포함
```

### Windows 데스크톱 빌드
플러그인 심링크가 UNC에서 실패하는 같은 이유로 `tool/build_windows.sh`를 쓴다
(Windows 쪽에서 `flutter run -d windows`로 바로 실행 가능):
```bash
tool/build_windows.sh release
# → build/windows/*.exe
```

### Android 에뮬레이터에서 실행 검증
```bash
# 1회: 에뮬레이터 패키지 + 시스템 이미지 설치, AVD 생성
#   sdkmanager 'emulator' 'system-images;android-36;google_apis;x86_64'
#   avdmanager create avd -n tikitaka -k system-images;android-36;google_apis;x86_64 -d pixel_5

# 이후: 부팅 → 릴리스 APK 설치 → 실행 → 크래시 검증
tool/build_android.sh release   # 최신 APK 빌드 (필요시)
tool/emulator_run.sh            # ✅ PID 확인 + FATAL 없음
```

## ⚠️ Android 실기기 네트워크 설정 (필수)

이 엔진은 로컬 Ollama 서버에 **HTTP(비보안)** 로 연결한다. Android 9(API 28) 이상에서는 기본적으로 cleartext HTTP 트래픽이 **차단**되므로, **호스트 앱**의 `AndroidManifest.xml`에 아래 설정 중 하나가 필요하다.

### 방법 A — usesCleartextTraffic (개발용·간단)
`android/app/src/main/AndroidManifest.xml`의 `<application>` 태그에 추가:
```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```
(예제 앱은 이미 적용되어 있음)

### 방법 B — networkSecurityConfig (권장·선별 허용)
`res/xml/network_security_config.xml` 생성:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <!-- 로컬 Ollama 주소만 허용 -->
        <domain includeSubdomains="false">10.0.2.2</domain>  <!-- 에뮬레이터 -->
        <domain includeSubdomains="false">192.168.x.x</domain> <!-- 실기기 LAN IP -->
    </domain-config>
</network-security-config>
```
매니페스트에 연결:
```xml
<application android:networkSecurityConfig="@xml/network_security_config" ...>
```

### 참고
- **에뮬레이터**: 호스트 PC의 Ollama는 `http://10.0.2.2:11434` 로 접근
- **실기기**: PC와 같은 Wi-Fi면 `http://<PC의 LAN IP>:11434`
- 앱 배포(Play Store) 시에는 방법 B 권장 — 방법 A는 보안 감사에서 지적될 수 있음

## 함대 배치
| 기기 | 모델 | 용도 |
|------|------|------|
| HermesA | lfm2.5-thinking:1.2b ✅ | PDF 파싱·빠른 판단 |
| HermesD | lfm2.5-thinking:1.2b ✅ | 배치 작업 |
| HermesB | lfm2.5-230m (설치 중) | 감시 판단 |
| TikiTaka | lfm2.5-thinking:1.2b 📱 | 학습 파트너 |


## 라이선스

MIT License — 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.
