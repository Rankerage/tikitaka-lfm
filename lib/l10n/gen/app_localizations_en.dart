// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get connectedStatus => 'LFM2.5 connected';

  @override
  String get offlineStatus => 'Offline — Ollama required';

  @override
  String get recheckTooltip => 'Recheck connection';

  @override
  String get connectedSnackbar => 'LFM2.5 connected';

  @override
  String get inputHint => 'Type your answer...';

  @override
  String get quizAction => 'Quiz';

  @override
  String get gradeAction => 'Grade';

  @override
  String get planAction => 'Plan';

  @override
  String get mistakeAction => 'Mistake';

  @override
  String get listenAction => 'Listen';

  @override
  String get connectionFailed => '⚠️ LFM2.5 connection failed. Check Ollama: ';

  @override
  String get evaluationFailed => '⚠️ Evaluation failed: ';

  @override
  String get planFailed => '⚠️ Plan generation failed: ';

  @override
  String get mistakeSaved => 'Saved to mistake book';

  @override
  String get planDialogTitle => 'Study plan';

  @override
  String get close => 'Close';
}
