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

/// 능동적 학습 파트너 엔진
class TikiTakaLfm {
  final LfmConfig config;
  final List<TkMessage> _history = [];

  final http.Client _client;
  final bool _ownsClient;

  /// 요청 시 모델에 전달할 최대 대화 메시지 수 (컨텍스트 오버플로 방지)
  static const int _maxContextMessages = 20;

  String _studySubject = '';
  int _quizIndex = 0;
  Timer? _proactiveTimer;

  /// [client]를 직접 주입하면 테스트에서 HTTP를 모킹할 수 있다.
  TikiTakaLfm({LfmConfig? config, http.Client? client})
      : config = config ?? const LfmConfig(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

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

  /// 학습 주제 설정
  void setSubject(String subject) => _studySubject = subject;

  /// 과목 + 메시지 조합
  String get _systemPrompt => '''
너는 티키타카(TikiTaka) 학습 파트너야.
주제: $_studySubject
- 항상 먼저 질문을 던져서 학습을 유도해 (티키타카 방식)
- 짧고 친근하게 대답해
- 맞으면 칭찬하고, 틀리면 힌트를 줘
- 마지막에 다음 질문 1개를 던져''';

  /// AI에게 메시지 보내기 (스트리밍 아님)
  ///
  /// 실패 시 방금 추가된 사용자 메시지를 되돌려(rollback) 기록 불일치를 방지한다.
  Future<String> ask(String userMessage) async {
    _history.add(TkMessage(role: 'user', content: userMessage));
    try {
      final reply = await _request(_recentHistory());
      _history.add(TkMessage(role: 'assistant', content: reply));
      await _saveHistory();
      return reply;
    } catch (_) {
      _history.removeLast(); // 답변 없이 남은 사용자 메시지 제거
      rethrow;
    }
  }

  /// 컨텍스트 오버플로를 막기 위해 최근 메시지만 추린다 (저장된 전체 기록은 유지)
  List<TkMessage> _recentHistory() {
    if (_history.length <= _maxContextMessages) return _history;
    return _history.sublist(_history.length - _maxContextMessages);
  }

  /// Ollama /api/chat 호출 (응답 파싱을 방어적으로 처리)
  Future<String> _request(List<TkMessage> messages) async {
    final body = jsonEncode({
      'model': config.model,
      'stream': false,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        ...messages.map((m) => {'role': m.role, 'content': m.content}),
      ],
    });

    final res = await _client
        .post(config.apiUrl,
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      throw Exception('LFM2.5 오류: HTTP ${res.statusCode}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final message = data is Map<String, dynamic> ? data['message'] : null;
    final reply = message is Map<String, dynamic> ? message['content'] : null;
    if (reply is! String) {
      throw Exception('LFM2.5 응답 형식 오류 (message.content 누락)');
    }
    return reply;
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

  /// 정답 평가 (간단한 규칙 기반 + AI)
  Future<String> grade(String answer) async {
    if (answer.length < 5) return '조금 더 길게 말해봐! 힌트: $_studySubject 핵심부터~';
    return ask('내가 말한 건데, 평가해주고 다음 문제 내줘: "$answer"');
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

  /// 엔진 리소스 정리 (프로액티브 타이머 해제, 소유한 HTTP 클라이언트 닫기)
  void dispose() {
    stopProactiveLearning();
    if (_ownsClient) {
      _client.close();
    }
  }

  /// 대화 기록 저장
  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_history.map((m) => m.toJson()).toList());
    await prefs.setString('tikitaka_history', json);
  }

  /// 대화 기록 불러오기 — 손상된 데이터는 무시하고 초기화한다
  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tikitaka_history');
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
    } catch (_) {
      // 손상된 기록은 버리고 키를 제거 (다음 로드에서도 실패하지 않도록)
      _history.clear();
      await prefs.remove('tikitaka_history');
    }
  }

  /// 초기화 (학습 리셋)
  Future<void> reset() async {
    _history.clear();
    _quizIndex = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tikitaka_history');
  }

  List<TkMessage> get history => List.unmodifiable(_history);
}
