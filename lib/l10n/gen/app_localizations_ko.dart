// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get connectedStatus => 'LFM2.5 온디바이스 연결됨';

  @override
  String get offlineStatus => '오프라인 — Ollama 필요';

  @override
  String get recheckTooltip => '연결 다시 확인';

  @override
  String get connectedSnackbar => 'LFM2.5 연결 확인됨';

  @override
  String get inputHint => '대답을 입력하세요...';

  @override
  String get quizAction => '문제';

  @override
  String get gradeAction => '평가';

  @override
  String get planAction => '계획';

  @override
  String get mistakeAction => '오답';

  @override
  String get listenAction => '듣기';

  @override
  String get connectionFailed => '⚠️ LFM2.5 연결 실패. Ollama 실행 확인: ';

  @override
  String get evaluationFailed => '⚠️ 평가 실패: ';

  @override
  String get planFailed => '⚠️ 학습 계획 생성 실패: ';

  @override
  String get mistakeSaved => '오답노트에 저장했습니다';

  @override
  String get planDialogTitle => '맞춤 학습 계획';

  @override
  String get close => '닫기';
}
