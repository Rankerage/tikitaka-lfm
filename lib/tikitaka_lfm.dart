/// TikiTaka LFM2.5 엔진 — Ollama 온디바이스 AI 학습 파트너
///
/// LFM2.5-1.2B (Liquid AI) 모델을 Ollama를 통해 로컬 실행.
/// - 오프라인 동작: 인터넷 없이도 학습 대화 가능
/// - 능동적 학습: AI가 먼저 질문을 던짐 (proactive)
/// - 학습 기록: SharedPreferences에 대화 저장
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// LFM2.5 모델 설정
class LfmConfig {
  final String host;
  final int port;
  final String model;

  const LfmConfig({
    this.host = '127.0.0.1',
    this.port = 11434,
    this.model = 'lfm2.5-thinking:1.2b',
  });

  Uri get apiUrl => Uri.parse('http://$host:$port/api/chat');

  /// Ollama 모델 목록 조회 URL
  Uri get tagsUrl => Uri.parse('http://$host:$port/api/tags');

  /// 안드로이드 에뮬레이터/실기기에서 PC Ollama 접근
  static const androidHost = '10.0.2.2'; // 에뮬레이터
  static const deviceHost = '192.168.0.100'; // 실기기 (변경 필요)
}

/// 대화 메시지
class TkMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;

  TkMessage({required this.role, required this.content, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'ts': timestamp.toIso8601String(),
      };

  factory TkMessage.fromJson(Map<String, dynamic> json) => TkMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['ts'] as String),
      );
}

/// 학습 활동 통계
class TkStats {
  /// 총 질문(성공한 대화) 수
  final int totalQuestions;

  /// 현재 연속 학습 일수
  final int streakDays;

  /// 역대 최고 연속 학습 일수
  final int bestStreak;

  /// 마지막 활동일 (자정 기준, 없으면 null)
  final DateTime? lastActive;

  const TkStats({
    required this.totalQuestions,
    required this.streakDays,
    required this.bestStreak,
    this.lastActive,
  });
}

/// 능동적 학습 파트너 엔진
class TikiTakaLfm {
  final LfmConfig config;
  final List<TkMessage> _history = [];

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;

  /// 요청 시 모델에 전달할 최대 대화 메시지 수 (컨텍스트 오버플로 방지)
  static const int _maxContextMessages = 20;

  /// 메모리·저장소에 보관할 최대 대화 메시지 수 (오래된 기록은 앞에서 제거)
  static const int _maxStoredMessages = 100;

  /// 기록 저장 디바운스 — 연속 대화 중 불필요한 중복 쓰기를 줄인다.
  final Duration saveDebounce;

  String _studySubject = '';
  int _quizIndex = 0;
  Timer? _proactiveTimer;
  Timer? _saveTimer;
  _Snapshot? _pending; // 디바운스 저장 대기 중인 스냅샷 (주제·데이터 고정)

  int _totalQuestions = 0;
  int _streakDays = 0;
  int _bestStreak = 0;
  DateTime? _lastActiveDate;

  /// [client]를 직접 주입하면 테스트에서 HTTP를 모킹할 수 있다.
  /// [clock]은 날짜 기반 통계(연속 학습) 테스트를 위해 주입한다.
  TikiTakaLfm({
    LfmConfig? config,
    http.Client? client,
    DateTime Function()? clock,
    this.saveDebounce = const Duration(milliseconds: 300),
  })  : config = config ?? const LfmConfig(),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _now = clock ?? DateTime.now;

  /// Ollama 연결 확인 — 설정된 모델(config.model) 패밀리가 로드돼 있는지 검사
  Future<bool> isAvailable() async {
    try {
      final res = await _client.get(config.tagsUrl).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map<String, dynamic>) return false;
      final models = data['models'];
      if (models is! List) return false;
      // 태그(:1.2b)와 무관하게 모델 패밀리만 비교해 버전 차이에도 대응
      final baseName = config.model.split(':').first;
      return models.any((m) {
        if (m is! Map) return false;
        final name = m['name'];
        return name is String && name.contains(baseName);
      });
    } catch (_) {
      return false;
    }
  }

  /// 학습 주제 설정 — 주제별로 대화 기록·통계가 분리된다.
  ///
  /// 주제를 바꾸면 현재 주제의 데이터를 메모리에서 내리고,
  /// 대기 중인 저장이 있으면 그 주제 키로 먼저 기록한다.
  /// 이후 [loadHistory]를 호출해 새 주제의 기록을 불러온다.
  void setSubject(String subject) {
    if (subject == _studySubject) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      unawaited(_writeSnapshot(pending)); // 이전 주제의 마지막 상태 저장 보장
    }
    _studySubject = subject;
    _history.clear();
    _totalQuestions = 0;
    _streakDays = 0;
    _bestStreak = 0;
    _lastActiveDate = null;
  }

  /// 과목 + 메시지 조합
  String get _systemPrompt => '''
너는 티키타카(TikiTaka) 학습 파트너야.
주제: $_studySubject
- 항상 먼저 질문을 던져서 학습을 유도해 (티키타카 방식)
- 짧고 친근하게 대답해
- 맞으면 칭찬하고, 틀리면 힌트를 줘
- 마지막에 다음 질문 1개를 던져''';

  /// AI에게 메시지 보내기 (스트리밍 아님 — 전체 답변을 기다려 반환)
  ///
  /// [askStream]을 그대로 사용한다 (히스토리 기록·롤백 동일).
  Future<String> ask(String userMessage) => askStream(userMessage).join();

  /// AI에게 메시지 보내기 (스트리밍) — 답변이 토큰 단위로 순서대로 내려온다.
  ///
  /// - 호출 즉시 사용자 메시지를 히스토리에 추가한다.
  /// - 스트림이 정상 완료되면 전체 답변을 히스토리에 저장한다(디바운스).
  /// - 오류나 소비자 취소 시 추가된 메시지를 되돌린다(rollback).
  Stream<String> askStream(String userMessage) async* {
    _append(TkMessage(role: 'user', content: userMessage));
    var committed = false;
    try {
      final buffer = StringBuffer();
      await for (final delta in _streamRequest(_recentHistory())) {
        buffer.write(delta);
        yield delta;
      }
      final reply = buffer.toString();
      _requireNonEmpty(reply);
      _append(TkMessage(role: 'assistant', content: reply));
      _recordActivity();
      _scheduleSave();
      committed = true;
    } finally {
      if (!committed) {
        // 사용자(+부분 답변) 메시지 롤백
        if (_history.isNotEmpty && _history.last.role == 'assistant') {
          _history.removeLast();
        }
        if (_history.isNotEmpty &&
            _history.last.role == 'user' &&
            _history.last.content == userMessage) {
          _history.removeLast();
        }
      }
    }
  }

  /// 대화 메시지를 추가하되 상한(_maxStoredMessages)을 넘으면 오래된 것부터 제거
  void _append(TkMessage message) {
    _history.add(message);
    if (_history.length > _maxStoredMessages) {
      _history.removeRange(0, _history.length - _maxStoredMessages);
    }
  }

  /// 성공한 대화 1회를 학습 활동으로 기록한다 (연속 학습 streak 갱신)
  void _recordActivity() {
    final today = _dateOnly(_now());
    final last = _lastActiveDate;
    _totalQuestions++;
    if (last == null) {
      _streakDays = 1;
    } else {
      final diff = today.difference(last).inDays;
      if (diff == 1) {
        _streakDays++; // 어제 활동 → 연속 유지
      } else if (diff > 1) {
        _streakDays = 1; // 하루 이상 건너뜀 → streak 리셋
      }
      // diff == 0: 같은 날 재활동 → 유지
    }
    if (_streakDays > _bestStreak) {
      _bestStreak = _streakDays;
    }
    _lastActiveDate = today;
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 학습 활동 통계 (연속 학습 일수 등)
  TkStats get stats => TkStats(
        totalQuestions: _totalQuestions,
        streakDays: _streakDays,
        bestStreak: _bestStreak,
        lastActive: _lastActiveDate,
      );

  /// 저장된 모든 과목의 통계를 반환한다 (과목 → [TkStats]).
  ///
  /// 저장 키를 스캔하며, 현재 주제는 저장 전 상태라도 메모리 값이 우선 반영된다.
  /// 기본 주제는 빈 문자열 키('')로 나타난다.
  Future<Map<String, TkStats>> allStats() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, TkStats>{};
    const prefix = 'tikitaka_total_questions';
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final suffix = key.substring(prefix.length); // '' 또는 '_수학'
      final subject = suffix.isEmpty ? '' : suffix.substring(1);
      result[subject] = TkStats(
        totalQuestions: prefs.getInt('tikitaka_total_questions$suffix') ?? 0,
        streakDays: prefs.getInt('tikitaka_streak_days$suffix') ?? 0,
        bestStreak: prefs.getInt('tikitaka_best_streak$suffix') ?? 0,
        lastActive: _parseLastActive(
            prefs.getString('tikitaka_last_active$suffix')),
      );
    }
    // 현재 주제는 저장 전 상태라도 메모리 기준 최신값으로 덮어쓴다
    result[_studySubject] = stats;
    return result;
  }

  static DateTime? _parseLastActive(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// 빈 답변 방어 — 형식 오류로 취급한다.
  void _requireNonEmpty(String reply) {
    if (reply.isEmpty) {
      throw const FormatException('LFM2.5 응답 형식 오류 (내용 없음)');
    }
  }

  /// 컨텍스트 오버플로를 막기 위해 최근 메시지만 추린다 (기록은 최근 N개 유지)
  List<TkMessage> _recentHistory() {
    if (_history.length <= _maxContextMessages) return _history;
    return _history.sublist(_history.length - _maxContextMessages);
  }

  /// Ollama /api/chat 스트리밍 호출 — 내용 조각(delta)을 순서대로 내보낸다.
  ///
  /// 응답은 줄 단위 JSON(NDJSON)이며, 각 줄의 `message.content`를 yield하고
  /// `done: true` 줄에서 종료한다. 비정상 응답은 [FormatException]을 던진다.
  Stream<String> _streamRequest(List<TkMessage> messages) async* {
    final body = jsonEncode({
      'model': config.model,
      'stream': true,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        ...messages.map((m) => {'role': m.role, 'content': m.content}),
      ],
    });

    final request = http.Request('POST', config.apiUrl)
      ..headers['Content-Type'] = 'application/json'
      ..body = body;

    final res =
        await _client.send(request).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      // 디버깅을 위해 서버가 준 오류 본문을 함께 전달
      String detail = '';
      try {
        detail = await res.stream
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // 본문을 읽지 못해도 상태 코드만으로 예외 처리
      }
      throw Exception('LFM2.5 오류: HTTP ${res.statusCode}${detail.isEmpty ? '' : ' — $detail'}');
    }

    await for (final line in res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 60))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        throw const FormatException('LFM2.5 응답 형식 오류 (JSON 파싱 실패)');
      }
      if (decoded is! Map<String, dynamic>) continue;
      final message = decoded['message'];
      if (message is! Map<String, dynamic>) continue;
      final content = message['content'];
      if (content is String && content.isNotEmpty) {
        yield content;
      }
      if (decoded['done'] == true) return; // 스트림 정상 종료
    }
    // done 없이 스트림이 끝난 경우(테스트 mock 등)도 정상 종료로 간주
  }

  /// AI가 먼저 말 걸기 (능동적 학습)
  String proactiveGreeting() {
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? '좋은 아침!'
        : hour < 17
            ? '안녕!'
            : '편안한 저녁!';
    return '$timeGreeting $_studySubject 공부 시작해볼까? '
        '오늘의 첫 문제 하나 던질게!';
  }

  /// 퀴즈 출제 (주제 기반)
  String makeQuiz() {
    final templates = [
      '자, "$_studySubject"에서 가장 어려웠던 개념 하나 말해볼래?',
      '$_studySubject 오늘 배운 내용 중 핵심 키워드 3개만 말해봐!',
      '내가 개념 하나 말할게. 설명해볼 수 있어?',
    ];
    return templates[_quizIndex++ % templates.length];
  }

  /// 학습 파트너가 먼저 건네는 메시지(퀴즈 등)를 히스토리에 추가한다.
  ///
  /// 모델을 호출하지 않으며, 활동 통계에도 기록되지 않는다.
  /// 이후 [ask] 호출 시 이 메시지가 컨텍스트에 포함되어 AI가 맥락을 안다.
  TkMessage tutorSay(String content) {
    final message = TkMessage(role: 'assistant', content: content);
    _append(message);
    _scheduleSave();
    return message;
  }

  /// 정답 평가 — '평가해줘' 요청이 대화 기록에 쌓인다 (학습 기록 보존용)
  ///
  /// 기록에 남기지 않고 1회성으로 평가하려면 [gradeDirect]를 사용한다.
  Future<String> grade(String answer) async {
    if (answer.length < 5) return '조금 더 길게 말해봐! 힌트: $_studySubject 핵심부터~';
    return ask('내가 말한 건데, 평가해주고 다음 문제 내줘: "$answer"');
  }

  /// 답변 평가 (1회성) — 히스토리에 남기지 않는 비파괴 평가 요청
  Future<String> gradeDirect(String answer) async {
    if (answer.length < 5) return '조금 더 길게 말해봐! 힌트: $_studySubject 핵심부터~';
    final buffer = StringBuffer();
    await for (final delta in _streamRequest([
      TkMessage(role: 'user', content: '내가 말한 답을 평가하고 힌트를 줘: "$answer"'),
    ])) {
      buffer.write(delta);
    }
    final reply = buffer.toString();
    _requireNonEmpty(reply);
    return reply;
  }

  /// 정기적인 능동적 학습 알림 시작
  ///
  /// [onTick]으로 인사말을 받아 실제 앱에서 push 알림 등을 발송할 수 있다.
  void startProactiveLearning({
    Duration interval = const Duration(hours: 1),
    void Function(String greeting)? onTick,
  }) {
    _proactiveTimer?.cancel();
    _proactiveTimer = Timer.periodic(interval, (_) {
      onTick?.call(proactiveGreeting());
    });
  }

  void stopProactiveLearning() {
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
  }

  /// 엔진 리소스 정리 (타이머 해제, 대기 중인 기록 저장 시도, HTTP 클라이언트 정리)
  void dispose() {
    stopProactiveLearning();
    _saveTimer?.cancel();
    _saveTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      unawaited(_writeSnapshot(pending)); // 마지막 기록 저장 시도 (비동기)
    }
    if (_ownsClient) {
      _client.close();
    }
  }

  /// 대화 기록 저장 예약 — [saveDebounce] 동안 추가 호출이 있으면 연기된다.
  ///
  /// 예약 시점의 (주제·데이터)를 스냅샷으로 고정하므로, 저장이 실행되기 전에
  /// 주제가 바뀌어도 잘못된 키로 쓰는 일이 없다.
  void _scheduleSave() {
    _pending = _currentSnapshot();
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, () {
      _saveTimer = null;
      final snap = _pending;
      _pending = null;
      if (snap != null) {
        unawaited(_writeSnapshot(snap));
      }
    });
  }

  /// 대기 중인 기록 저장을 즉시 수행한다 (앱 종료 전·테스트에서 사용).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final snap = _pending ?? _currentSnapshot();
    _pending = null;
    await _writeSnapshot(snap);
  }

  _Snapshot _currentSnapshot() => _Snapshot(
        subject: _studySubject,
        history: List<TkMessage>.of(_history),
        totalQuestions: _totalQuestions,
        streakDays: _streakDays,
        bestStreak: _bestStreak,
        lastActive: _lastActiveDate,
      );

  /// 한 과목의 기록·통계를 주제별 키로 저장한다 (실제 SharedPreferences 쓰기)
  Future<void> _writeSnapshot(_Snapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = snap.subject.isEmpty ? '' : '_${snap.subject}';
    final json =
        jsonEncode(snap.history.map((m) => m.toJson()).toList());
    await prefs.setString('tikitaka_history$suffix', json);
    await prefs.setInt('tikitaka_total_questions$suffix', snap.totalQuestions);
    await prefs.setInt('tikitaka_streak_days$suffix', snap.streakDays);
    await prefs.setInt('tikitaka_best_streak$suffix', snap.bestStreak);
    await prefs.setString('tikitaka_last_active$suffix',
        snap.lastActive?.toIso8601String() ?? '');
  }

  /// 대화 기록 불러오기 (현재 주제 기준) — 손상된 데이터는 무시하고 초기화한다
  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    // 통계는 히스토리와 독립적으로 복원
    _totalQuestions = prefs.getInt('tikitaka_total_questions$_suffix') ?? 0;
    _streakDays = prefs.getInt('tikitaka_streak_days$_suffix') ?? 0;
    _bestStreak = prefs.getInt('tikitaka_best_streak$_suffix') ?? 0;
    final last = prefs.getString('tikitaka_last_active$_suffix');
    _lastActiveDate = last == null || last.isEmpty
        ? null
        : DateTime.tryParse(last);

    final raw = prefs.getString('tikitaka_history$_suffix');
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) throw const FormatException('기록 형식 오류');
      final loaded = <TkMessage>[
        for (final e in list)
          if (e is Map<String, dynamic>) TkMessage.fromJson(e),
      ];
      _history
        ..clear()
        ..addAll(loaded);
      if (_history.length > _maxStoredMessages) {
        _history.removeRange(0, _history.length - _maxStoredMessages);
      }
    } catch (_) {
      // 손상된 기록은 버리고 키를 제거 (다음 로드에서도 실패하지 않도록)
      _history.clear();
      await prefs.remove('tikitaka_history$_suffix');
    }
  }

  /// 초기화 (현재 주제 학습 리셋) — 대기 중인 저장도 취소해 이전 기록이 되살아나지 않게 한다.
  ///
  /// 대화 기록·질문 수·현재 streak은 초기화되지만 역대 최고 streak은 유지된다.
  Future<void> reset() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pending = null;
    _history.clear();
    _quizIndex = 0;
    _totalQuestions = 0;
    _streakDays = 0;
    _lastActiveDate = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tikitaka_history$_suffix');
    await prefs.remove('tikitaka_total_questions$_suffix');
    await prefs.remove('tikitaka_streak_days$_suffix');
    await prefs.remove('tikitaka_last_active$_suffix');
    if (_bestStreak > 0) {
      await prefs.setInt('tikitaka_best_streak$_suffix', _bestStreak);
    }
  }

  /// 현재 주제의 저장 키 접미사 (기본 주제는 빈 문자열 → 기존 키 호환)
  String get _suffix => _studySubject.isEmpty ? '' : '_$_studySubject';

  List<TkMessage> get history => List.unmodifiable(_history);
}

/// 특정 시점의 한 과목 기록·통계 스냅샷 — 디바운스 저장의 원자적 단위
class _Snapshot {
  final String subject;
  final List<TkMessage> history;
  final int totalQuestions;
  final int streakDays;
  final int bestStreak;
  final DateTime? lastActive;

  const _Snapshot({
    required this.subject,
    required this.history,
    required this.totalQuestions,
    required this.streakDays,
    required this.bestStreak,
    required this.lastActive,
  });
}
