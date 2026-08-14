# Changelog

이 프로젝트의 변경 이력. 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 기반.

## [1.3.0] - 2026-08-14

### Added
- **일별 활동 추적** — `weeklyActivity()` 최근 7일 질문 수, 통계 화면 막대 그래프
- **과목 데이터 삭제** — `deleteSubject()` 기록·오답노트·통계 전체 제거
- **이번 주 활동 요약** — `exportHistory()`에 주간 질문 수·활동 일수
- **음성(TTS) 학습** — 채팅 '듣기' 버튼·복습 카드 발음(질문·답), 과목별 언어
- **에뮬레이터 E2E** — `integration_test/app_e2e_test.dart` 설정→연결→대화 검증

### Fixed
- 좁은 화면 액션 칩 가로 오버플로 (가로 스크롤)
- 설정 시트 controller use-after-dispose (StatefulWidget 리팩터링)
- Windows 빌드: flutter_tts에 필요한 nuget.exe 자동 안내

### Changed
- 버전 1.3.0 (versionCode 4)

## [1.2.0] - 2026-08-14

### Added
- **학습 알림** — flutter_local_notifications 매일 반복 로컬 알림, 설정 스위치 (core library desugaring + POST_NOTIFICATIONS)
- **일별 활동 추적** — `weeklyActivity()` 최근 7일 질문 수, 통계 화면 막대 그래프 (30일 보관)
- **과목 데이터 삭제** — `deleteSubject()` 기록·오답노트·통계 전체 제거, 통계 화면 확인 대화상자
- **이번 주 활동 요약** — `exportHistory()`에 주간 질문 수·활동 일수 포함
- **음성(TTS) 학습** — `TikiTakaChat.onSpeak` 콜백 + '듣기' 버튼, 복습 카드 발음, 과목별 언어(영어→en-US)
- **에뮬레이터 실행 검증** — AVD 'tikitaka' 구성, `tool/emulator_run.sh`로 릴리스 APK 설치·실행·크래시 검증 (Android 16/API 36, WHPX)
- **E2E 통합 테스트** — `integration_test/app_e2e_test.dart`가 에뮬레이터에서 설정 변경→실제 Ollama 연결→AI 응답까지 검증
- **E2E가 잡은 버그 수정** — 좁은 화면 액션 칩 가로 오버플로(스크롤 처리), 설정 시트 controller use-after-dispose(StatefulWidget 리팩터링)
- **오답노트** — 과목별 저장, 채팅 '오답' 버튼, 통계 화면 목록·내보내기 포함
- **오답노트 복습** — `nextMistakeReview()` 순환 플래시카드, 정답 보기·맞았어요 삭제
- **AI 보조 기능** — `summarize()`·`learningPlan()` (실제 모델 통합 검증)
- **앱 브랜딩** — 티키타카 런처 아이콘·적응형 아이콘·네이티브 스플래시
- **GitHub Actions CI** — `.github/workflows/ci.yml`
- **릴리스 산출물** — 서명 APK·Play AAB·Web·Windows 데스크톱

### Changed
- 버전 1.2.0 (versionCode 3), 앱 정보 다이얼로그

## [1.1.0] - 2026-08-14

### Added
- **과목별 통계 화면** — `allStats()`로 전체 과목 streak/질문 수 조회, example 앱에 통계 페이지(📊) 추가
- **과목별 히스토리·통계 분리** — `setSubject()` 전환 시 주제별 키로 저장 (기본 주제는 기존 키 호환)
- **오늘의 문제/평가 플로우** — `tutorSay()`(모델 호출 없는 조교 메시지) + 채팅 '문제/평가' 액션 버튼
- **학습 통계** — `TkStats`(총 질문 수, 연속 streak, 최고 streak, 마지막 활동일), `clock` 주입으로 테스트 가능
- **스트리밍 답변** — `askStream()` (Ollama `stream:true` NDJSON 파싱), UI 실시간 표시
- **실제 Ollama 통합 테스트** — `test/integration_stream_test.dart` (환경변수로 대상 설정, 없으면 자동 skip)
- **릴리스 빌드** — `tool/build_android.sh` (NTFS 복사 빌드), `build/apk/app-release.apk`
- **웹 데모** — `flutter build web` 검증, `example/web` 메타데이터 정리
- **Windows 데스크톱 빌드** — `tool/build_windows.sh`
- **릴리스 서명** — `tikitaka-release.jks` + `key.properties`(git 제외), 디버그 키 폴백
- **기록 내보내기** — `exportHistory()` 마크다운(Obsidian용), 통계 화면에서 클립보드 복사
- **퀴즈 템플릿 확장** — `makeQuiz()` 3→8개 유형 순환
- **GitHub Actions CI** — `.github/workflows/ci.yml` (analyze + test, 루트/example)
- **AI 학습 요약** — `summarize(maxLines)` 중립 프롬프트로 최근 대화 요약 (비히스토리)
- **App Bundle** — `tool/build_android.sh bundle` → Play 스토어용 `app-release.aab` (릴리스 키 서명)
- **요약 UI** — 통계 화면에서 `summarize()` 호출, 결과 대화상자 표시 (통합 테스트에서 실제 모델 검증)
- **맞춤 학습 계획** — `learningPlan(minutes)` 최근 대화·통계 기반 계획 생성, 채팅 '계획' 버튼 (실제 모델 통합 검증)
- **앱 브랜딩** — 티키타카 런처 아이콘(패싱볼 모티프)·적응형 아이콘·네이티브 스플래시 (flutter_launcher_icons / flutter_native_splash)
- **앱 정보 다이얼로그** — 버전·엔진·모델 정보 표시
- **릴리스 정리** — 버전 1.1.0 (versionCode 2), Android/Web/Windows 전체 재검증
- **오답노트** — `addMistake`/`removeMistake`/`clearMistakes` (과목별 저장), 채팅 '오답' 버튼, 통계 화면 목록·내보내기 포함
- **오답노트 복습** — `nextMistakeReview()` 순환 플래시카드, 통계 화면 '복습' 진입 (정답 보기·맞았어요 삭제)
- **학습 알림** — flutter_local_notifications 매일 반복 알림, 설정 스위치 (core library desugaring + POST_NOTIFICATIONS)

### Changed
- `ask()`를 `askStream().join()`으로 재구성 (코드 경로 통일)
- 저장 디바운스: `saveDebounce`(기본 300ms) + `flush()` — 스냅샷 기반으로 주제 전환 시 유실 방지
- 기록 상한: 메모리·저장소 모두 최근 100개 유지
- HTTP 오류 메시지에 서버 응답 본문 포함
- `TikiTakaChat`에 `onActivity`, `showActions` 옵션 추가

### Fixed
- `flutter_test` HTTP 모킹(전 요청 400)이 실제 Ollama 접속을 막는 문제 회피
- 다이얼로그 닫힘 애니메이션 중 TextEditingController use-after-dispose
- `withOpacity` deprecated → `withValues`

## [1.0.0] - 2026-08-14

### Added
- 최초 베이스라인: 엔진(`TikiTakaLfm`)·채팅 위젯(`TikiTakaChat`)·example 앱
- 엔진 단위 테스트 17개, example 위젯 테스트, Android APK 빌드 워크플로
- `http.Client` 주입 가능한 리팩터링 (테스트 용이성)
