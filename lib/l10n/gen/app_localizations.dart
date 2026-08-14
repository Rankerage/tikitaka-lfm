import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko')
  ];

  /// No description provided for @connectedStatus.
  ///
  /// In ko, this message translates to:
  /// **'LFM2.5 온디바이스 연결됨'**
  String get connectedStatus;

  /// No description provided for @offlineStatus.
  ///
  /// In ko, this message translates to:
  /// **'오프라인 — Ollama 필요'**
  String get offlineStatus;

  /// No description provided for @recheckTooltip.
  ///
  /// In ko, this message translates to:
  /// **'연결 다시 확인'**
  String get recheckTooltip;

  /// No description provided for @connectedSnackbar.
  ///
  /// In ko, this message translates to:
  /// **'LFM2.5 연결 확인됨'**
  String get connectedSnackbar;

  /// No description provided for @inputHint.
  ///
  /// In ko, this message translates to:
  /// **'대답을 입력하세요...'**
  String get inputHint;

  /// No description provided for @quizAction.
  ///
  /// In ko, this message translates to:
  /// **'문제'**
  String get quizAction;

  /// No description provided for @gradeAction.
  ///
  /// In ko, this message translates to:
  /// **'평가'**
  String get gradeAction;

  /// No description provided for @planAction.
  ///
  /// In ko, this message translates to:
  /// **'계획'**
  String get planAction;

  /// No description provided for @mistakeAction.
  ///
  /// In ko, this message translates to:
  /// **'오답'**
  String get mistakeAction;

  /// No description provided for @listenAction.
  ///
  /// In ko, this message translates to:
  /// **'듣기'**
  String get listenAction;

  /// No description provided for @connectionFailed.
  ///
  /// In ko, this message translates to:
  /// **'⚠️ LFM2.5 연결 실패. Ollama 실행 확인: '**
  String get connectionFailed;

  /// No description provided for @evaluationFailed.
  ///
  /// In ko, this message translates to:
  /// **'⚠️ 평가 실패: '**
  String get evaluationFailed;

  /// No description provided for @planFailed.
  ///
  /// In ko, this message translates to:
  /// **'⚠️ 학습 계획 생성 실패: '**
  String get planFailed;

  /// No description provided for @mistakeSaved.
  ///
  /// In ko, this message translates to:
  /// **'오답노트에 저장했습니다'**
  String get mistakeSaved;

  /// No description provided for @planDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'맞춤 학습 계획'**
  String get planDialogTitle;

  /// No description provided for @close.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get close;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
