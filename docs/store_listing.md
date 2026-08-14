# TikiTaka — 앱 스토어 리스팅

## 앱 설명

### 한국어
**🎯 TikiTaka — 온디바이스 AI 학습 파트너**

AI가 먼저 말을 걸고, 질문을 던지고, 학습을 이끄는 온디바이스 학습 파트너입니다.
모든 대화는 기기 안에서 처리되어 프라이버시가 100% 보장됩니다 (인터넷 불필요).

- **능동적 학습**: AI가 먼저 인사하고 문제를 내며 학습을 유도합니다
- **오늘의 문제/평가/계획**: 퀴즈 → 평가 → 맞춤 학습 계획의 완전한 학습 사이클
- **오답노트 + 플래시카드 복습**: 틀린 문제를 자동 저장하고 순환 복습
- **연속 학습 streak**: 날마다 이어지는 학습 습관, 최근 7일 활동 그래프
- **학습 알림**: 매일 공부할 시간에 알림
- **음성 학습**: 질문·답변을 소리로 듣고 발음 연습 (영어/한국어)
- **과목별 기록**: 수학·영어·과학 등 과목별로 기록·통계·오답노트 분리
- **Obsidian 연동**: 학습 기록을 마크다운으로 내보내 노트로 보관

### English
**🎯 TikiTaka — On-Device AI Learning Partner**

An AI that starts conversations, asks questions, and drives your learning — fully
on-device with 100% privacy (no internet required).

- Proactive learning: the AI greets you first and leads with questions
- Quiz → evaluation → personalized study plan loop
- Mistake book with flashcard review
- Daily streaks and 7-day activity charts
- Daily study reminders
- Text-to-speech pronunciation practice (English/Korean)
- Per-subject history, stats, and mistake tracking
- Export study notes to Obsidian as Markdown

## 스크린샷

| 파일 | 내용 |
|---|---|
| `01_home_chat.png` | 홈 — 채팅 (AI가 먼저 질문) |
| `02_stats.png` | 통계 — 과목별 streak · 7일 활동 그래프 · 오답노트 |
| `03_review_empty.png` | 오답노트 복습 (플래시카드) |
| `04_settings.png` | 설정 — Ollama 연결 · 학습 알림 |
| `05_about.png` | 앱 정보 |

## 카테고리·메타

- **카테고리**: 교육 (Education)
- **키워드**: 학습, AI, 온디바이스, 퀴즈, 오답노트, 영어, 수학, streak
- **요구사항**: Android 8.0+ (API 26+), Ollama 서버(선택 — 오프라인/온디바이스 모델 포함)

## 스크린샷 재캡처 방법

```bash
# 에뮬레이터 부팅 후 (tool/emulator_run.sh 참고)
tool/build_android.sh release   # 최신 APK (필요시)
cd example
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart -d emulator-5554
# → docs/screenshots/ (C: 사본의 screenshots/에서 복사)
```
