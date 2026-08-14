# TikiTaka 예제 앱

티키타카 LFM2.5 엔진을 실제로 실행해볼 수 있는 Flutter 앱입니다.

## 실행
```bash
# 1. Ollama에 모델 설치 (PC)
ollama pull lfm2.5-thinking:1.2b

# 2. 예제 앱 실행
cd example
flutter pub get
flutter run          # 연결된 기기/에뮬레이터 선택

# 웹 데모 빌드 + 로컬 서빙
flutter build web --release
cd build/web && python3 -m http.server 8080   # http://localhost:8080
```

> **웹에서 Ollama 호출**: 브라우저 CORS 때문에 Ollama 서버가
> `OLLAMA_ORIGINS=http://localhost:8080 ollama serve` 형태로 origin을 허용해야 한다.

## Ollama 연결 주소
| 실행 대상 | 호스트 | 비고 |
|---|---|---|
| 데스크톱(Windows) | `127.0.0.1` | 기본값 |
| Android 에뮬레이터 | `10.0.2.2` | 호스트 PC의 localhost |
| Android 실기기 | `<PC의 LAN IP>` | 같은 Wi-Fi 필요 |

앱 안의 **설정(⚙️)** 버튼에서 호스트/포트/모델을 바꿀 수 있으며 저장됩니다.

## Android 참고
- 예제 앱의 매니페스트에는 개발용으로 `android:usesCleartextTraffic="true"`와
  `INTERNET` 권한이 이미 적용되어 있습니다. 배포 시에는
  `networkSecurityConfig` 방식으로 전환하세요 (루트 README 참고).
- Ollama 서버는 기본적으로 `0.0.0.0:11434`에서 수신 대기해야 실기기에서 접근
  가능합니다: `OLLAMA_HOST=0.0.0.0 ollama serve`

## 테스트
```bash
cd example
flutter analyze
flutter test
```
