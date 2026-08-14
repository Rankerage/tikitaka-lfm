# Changelog

이 프로젝트의 변경 이력. 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 기반.

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
