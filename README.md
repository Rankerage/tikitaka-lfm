# 🎯 TikiTaka LFM2.5 엔진

**능동적 학습 파트너** — AI가 먼저 말 걸고, 학습을 시키는 온디바이스 엔진.

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
```

## 능동적 학습
- `proactiveGreeting()` — AI가 먼저 인사 + 학습 유도
- `makeQuiz()` — 주제 기반 퀴즈 자동 출제
- `startProactiveLearning(interval, onTick)` — 정기 학습 알림 (onTick으로 push 연동)
- 오프라인 완전 동작 (인터넷 불필요)

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
