import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tikitaka_lfm/tikitaka_lfm.dart';

/// 요청 기록을 남기는 MockClient 헬퍼
MockClient _mock(
  http.Response Function(http.Request) onRequest, {
  List<http.Request>? log,
}) {
  return MockClient((request) async {
    log?.add(request);
    return onRequest(request);
  });
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _chatReply(String content) =>
    _json({'message': {'role': 'assistant', 'content': content}});

/// NDJSON 스트리밍 응답 (Ollama stream:true 형태)
http.Response streamReply(List<String> chunks, {bool done = true}) {
  final lines = [
    for (final c in chunks)
      jsonEncode({'message': {'role': 'assistant', 'content': c}}),
    if (done)
      jsonEncode({
        'message': {'role': 'assistant', 'content': ''},
        'done': true,
      }),
  ].join('\n');
  return http.Response(lines, 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LfmConfig', () {
    test('기본값은 로컬 Ollama 11434', () {
      const c = LfmConfig();
      expect(c.host, '127.0.0.1');
      expect(c.port, 11434);
      expect(c.model, 'lfm2.5-thinking:1.2b');
      expect(c.apiUrl.toString(), 'http://127.0.0.1:11434/api/chat');
      expect(c.tagsUrl.toString(), 'http://127.0.0.1:11434/api/tags');
    });
  });

  group('isAvailable', () {
    test('모델 패밀리가 있으면 true (태그 무관)', () async {
      final client = _mock((req) => _json({
            'models': [
              {'name': 'lfm2.5-thinking:1.2b'},
              {'name': 'nomic-embed-text:latest'},
            ]
          }));
      final engine = TikiTakaLfm(client: client);
      expect(await engine.isAvailable(), isTrue);
      engine.dispose();
    });

    test('비-200 응답이면 false', () async {
      final client = _mock((req) => http.Response('oops', 500));
      final engine = TikiTakaLfm(client: client);
      expect(await engine.isAvailable(), isFalse);
      engine.dispose();
    });

    test('모델이 없으면 false', () async {
      final client = _mock((req) => _json({'models': <dynamic>[]}));
      final engine = TikiTakaLfm(client: client);
      expect(await engine.isAvailable(), isFalse);
      engine.dispose();
    });

    test('네트워크 오류면 false (예외 방출 안 함)', () async {
      final client = MockClient((req) async => throw http.ClientException('refused'));
      final engine = TikiTakaLfm(client: client);
      expect(await engine.isAvailable(), isFalse);
      engine.dispose();
    });
  });

  group('ask', () {
    test('POST /api/chat 호출 후 답변 반환 + 히스토리 저장', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('안녕! 오늘은 뭘 배워볼까?'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');

      final reply = await engine.ask('이차방정식 어려워요');

      expect(reply, '안녕! 오늘은 뭘 배워볼까?');
      expect(log, hasLength(1));
      expect(log.single.url.toString(), 'http://127.0.0.1:11434/api/chat');

      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['model'], 'lfm2.5-thinking:1.2b');
      expect(body['stream'], true);
      final messages = body['messages'] as List;
      expect(messages.first['role'], 'system');
      expect((messages.first['content'] as String), contains('수학'));

      // 히스토리 유지
      expect(engine.history, hasLength(2));
      expect(engine.history.first.role, 'user');
      expect(engine.history.last.role, 'assistant');
      engine.dispose();
    });

    test('실패 시 사용자 메시지 롤백 + 예외 전파', () async {
      final client = MockClient((req) async => http.Response('err', 500));
      final engine = TikiTakaLfm(client: client);

      await expectLater(engine.ask('안녕'), throwsException);
      expect(engine.history, isEmpty);
      engine.dispose();
    });

    test('컨텍스트 캡: 20개 초과 시 최근 20개만 전송', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('ok'), log: log);
      final engine = TikiTakaLfm(client: client);

      // 25턴(유저+어시스턴트 = 50 메시지) 진행
      for (var i = 0; i < 25; i++) {
        await engine.ask('메시지 $i');
      }

      final body = jsonDecode(log.last.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      // system + 최근 20개
      expect(messages, hasLength(21));
      // 윈도우 밖의 오래된 메시지는 전송되지 않음
      final sent = jsonEncode(messages);
      expect(sent, isNot(contains('메시지 6')));
      // 최신 메시지는 포함
      expect(sent, contains('메시지 24'));
      expect(engine.history, hasLength(50)); // 저장된 전체 기록은 유지
      engine.dispose();
    });
  });

  group('askStream (스트리밍)', () {
    test('델타를 순서대로 내보내고 완료 시 히스토리 저장', () async {
      final log = <http.Request>[];
      final client = _mock((req) => streamReply(['안', '녕', '!']), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('과학');

      final deltas = await engine.askStream('광합성이 뭐예요?').toList();

      expect(deltas, ['안', '녕', '!']);
      // 요청은 stream:true
      expect(jsonDecode(log.single.body)['stream'], true);
      // 히스토리 저장
      expect(engine.history, hasLength(2));
      expect(engine.history.last.content, '안녕!');
      engine.dispose();
    });

    test('HTTP 오류 시 사용자 메시지 롤백 + 예외 전파', () async {
      final client = MockClient((req) async => http.Response('err', 500));
      final engine = TikiTakaLfm(client: client);

      await expectLater(
          engine.askStream('안녕').toList(), throwsException);
      expect(engine.history, isEmpty);
      engine.dispose();
    });

    test('비정상 JSON 줄은 FormatException + 롤백', () async {
      final client = _mock((req) =>
          http.Response('{broken json\n{"message":{"content":"x"}}', 200,
              headers: {'content-type': 'application/json; charset=utf-8'}));
      final engine = TikiTakaLfm(client: client);

      await expectLater(
        engine.askStream('질문').toList(),
        throwsA(isA<FormatException>()),
      );
      expect(engine.history, isEmpty);
      engine.dispose();
    });

    test('내용 없이 done이 오면 오류 + 롤백', () async {
      final client = _mock((req) => streamReply([], done: true));
      final engine = TikiTakaLfm(client: client);

      await expectLater(
        engine.askStream('질문').toList(),
        throwsA(isA<FormatException>()),
      );
      expect(engine.history, isEmpty);
      engine.dispose();
    });

    test('ask()는 askStream의 join과 동일한 결과', () async {
      final client = _mock((req) => streamReply(['정', '답', '!']));
      final engine = TikiTakaLfm(client: client);
      final reply = await engine.ask('2+2는?');
      expect(reply, '정답!');
      expect(engine.history, hasLength(2));
      engine.dispose();
    });
  });

  group('loadHistory / reset', () {
    test('저장된 기록 복원 (flush 후)', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      await engine.ask('첫 질문');
      await engine.flush(); // 디바운스된 저장을 즉시 확정
      // 새 엔진으로 복원
      final engine2 = TikiTakaLfm(client: client);
      await engine2.loadHistory();
      expect(engine2.history, hasLength(2));
      expect(engine2.history.first.content, '첫 질문');
      engine.dispose();
      engine2.dispose();
    });

    test('디바운스: flush 전에는 저장되지 않음, flush 후에는 저장됨', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(
          client: client, saveDebounce: const Duration(minutes: 1));
      await engine.ask('아직 저장 안 됨');

      // 플러시 전: 새 엔진은 아무것도 못 봄
      final before = TikiTakaLfm(client: client);
      await before.loadHistory();
      expect(before.history, isEmpty);

      // 플러시 후: 저장 확인
      await engine.flush();
      final after = TikiTakaLfm(client: client);
      await after.loadHistory();
      expect(after.history, hasLength(2));
      engine.dispose();
      before.dispose();
      after.dispose();
    });

    test('디바운스: 대기 시간이 지나면 자동 저장', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(
          client: client, saveDebounce: const Duration(milliseconds: 30));
      await engine.ask('자동 저장');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final loaded = TikiTakaLfm(client: client);
      await loaded.loadHistory();
      expect(loaded.history, hasLength(2));
      engine.dispose();
      loaded.dispose();
    });

    test('reset은 대기 중인 저장을 취소해 기록이 되살아나지 않는다', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(
          client: client, saveDebounce: const Duration(milliseconds: 30));
      await engine.ask('지워질 기록');
      await engine.reset();
      await Future<void>.delayed(const Duration(milliseconds: 120)); // 타이머가 돌아도

      final loaded = TikiTakaLfm(client: client);
      await loaded.loadHistory();
      expect(loaded.history, isEmpty);
      engine.dispose();
      loaded.dispose();
    });

    test('기록 상한: 100개 초과 시 오래된 메시지부터 제거', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      // 55턴 = 110 메시지 → 최근 100개만 유지
      for (var i = 0; i < 55; i++) {
        await engine.ask('메시지 $i');
      }
      expect(engine.history, hasLength(100));
      // 첫 5턴(10개)이 제거되고 '메시지 5'부터 시작
      expect(engine.history.first.content, '메시지 5');
      expect(engine.history.last.role, 'assistant');

      // 저장된 데이터도 100개
      await engine.flush();
      final loaded = TikiTakaLfm(client: client);
      await loaded.loadHistory();
      expect(loaded.history, hasLength(100));
      expect(loaded.history.first.content, '메시지 5');
      engine.dispose();
      loaded.dispose();
    });

    test('손상된 기록은 크래시 없이 초기화', () async {
      SharedPreferences.setMockInitialValues(
          {'tikitaka_history': '{not valid json'});
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      await engine.loadHistory(); // throw 없이 통과해야 함
      expect(engine.history, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tikitaka_history'), isNull);
      engine.dispose();
    });

    test('reset은 기록과 퀴즈 인덱스를 초기화', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      await engine.ask('질문');
      engine.makeQuiz();
      await engine.reset();
      expect(engine.history, isEmpty);
      // 인덱스가 리셋되어 첫 템플릿부터
      expect(engine.makeQuiz(), contains('가장 어려웠던 개념'));
      engine.dispose();
    });
  });

  group('퀴즈 / 인사말 / 평가', () {
    test('makeQuiz는 8개 템플릿을 순환', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.setSubject('영어');
      final seen = <String>[];
      for (var i = 0; i < 8; i++) {
        seen.add(engine.makeQuiz());
      }
      // 8개 템플릿이 모두 서로 다르다
      expect(seen.toSet(), hasLength(8));
      // 9번째 호출은 첫 템플릿으로 순환
      expect(engine.makeQuiz(), equals(seen.first));
      engine.dispose();
    });

    test('proactiveGreeting은 주제를 포함한 인사말', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.setSubject('과학');
      final g = engine.proactiveGreeting();
      expect(g, contains('과학'));
      expect(g, anyOf(contains('아침'), contains('안녕'), contains('저녁')));
      engine.dispose();
    });

    test('grade: 5자 미만 답변은 AI 호출 없이 힌트', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('ok'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      final r = await engine.grade('네');
      expect(r, contains('조금 더 길게'));
      expect(log, isEmpty);
      engine.dispose();
    });

    test('grade: 충분한 답변은 AI 평가 호출', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('좋아요, 정답!'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      final r = await engine.grade('x = 2입니다');
      expect(r, '좋아요, 정답!');
      expect(log, hasLength(1));
      engine.dispose();
    });

    test('gradeDirect: 히스토리에 남기지 않고 1회성 평가', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('힌트: 근의 공식을 떠올려봐!'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');

      final r = await engine.gradeDirect('x = (-b ± √(b²-4ac)) / 2a');

      expect(r, contains('근의 공식'));
      expect(log, hasLength(1));
      // 히스토리 비파괴: 어떤 메시지도 남지 않는다
      expect(engine.history, isEmpty);
      engine.dispose();
    });

    test('gradeDirect: 5자 미만 답변은 AI 호출 없이 힌트', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('ok'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      final r = await engine.gradeDirect('네');
      expect(r, contains('조금 더 길게'));
      expect(log, isEmpty);
      expect(engine.history, isEmpty);
      engine.dispose();
    });

    test('gradeDirect: 빈 응답이면 FormatException', () async {
      final client = _mock((req) => streamReply([], done: true));
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await expectLater(
        engine.gradeDirect('충분히 긴 답변입니다'),
        throwsA(isA<FormatException>()),
      );
      expect(engine.history, isEmpty);
      engine.dispose();
    });
  });

  group('학습 통계 (streak)', () {
    test('첫 활동: streak 1, 질문 수 1', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('시작');
      final s = engine.stats;
      expect(s.totalQuestions, 1);
      expect(s.streakDays, 1);
      expect(s.bestStreak, 1);
      expect(s.lastActive, DateTime(2026, 8, 14));
      engine.dispose();
    });

    test('같은 날 여러 번 활동해도 streak 유지', () async {
      var now = DateTime(2026, 8, 14, 9, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('1');
      now = DateTime(2026, 8, 14, 21, 30);
      await engine.ask('2');
      await engine.ask('3');
      expect(engine.stats.totalQuestions, 3);
      expect(engine.stats.streakDays, 1);
      expect(engine.stats.bestStreak, 1);
      engine.dispose();
    });

    test('다음 날 활동하면 streak 증가', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('1일차');
      now = DateTime(2026, 8, 15, 8, 0);
      await engine.ask('2일차');
      now = DateTime(2026, 8, 16, 22, 0);
      await engine.ask('3일차');
      expect(engine.stats.streakDays, 3);
      expect(engine.stats.bestStreak, 3);
      engine.dispose();
    });

    test('하루 이상 건너뛰면 streak 리셋 (best는 유지)', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('1일차');
      now = DateTime(2026, 8, 15, 10, 0);
      await engine.ask('2일차');
      expect(engine.stats.streakDays, 2);
      now = DateTime(2026, 8, 18, 10, 0); // 3일 건너뜀
      await engine.ask('새 시작');
      expect(engine.stats.streakDays, 1);
      expect(engine.stats.bestStreak, 2);
      engine.dispose();
    });

    test('통계 영속화: flush 후 새 엔진에서 복원', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client, clock: () => now);
      await engine.ask('1');
      now = DateTime(2026, 8, 15, 10, 0);
      await engine.ask('2');
      await engine.flush();

      final restored = TikiTakaLfm(client: client);
      await restored.loadHistory();
      expect(restored.stats.totalQuestions, 2);
      expect(restored.stats.streakDays, 2);
      expect(restored.stats.bestStreak, 2);
      expect(restored.stats.lastActive, DateTime(2026, 8, 15));
      engine.dispose();
      restored.dispose();
    });

    test('reset: 질문 수·streak 초기화, best streak은 유지', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('1');
      now = DateTime(2026, 8, 15, 10, 0);
      await engine.ask('2');
      expect(engine.stats.bestStreak, 2);

      await engine.reset();
      expect(engine.stats.totalQuestions, 0);
      expect(engine.stats.streakDays, 0);
      expect(engine.stats.lastActive, isNull);
      expect(engine.stats.bestStreak, 2); // 개인 최고 기록은 유지
      engine.dispose();
    });

    test('gradeDirect는 활동으로 기록되지 않는다', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('좋아요!')), clock: () => now);
      await engine.gradeDirect('충분히 긴 답변입니다');
      expect(engine.stats.totalQuestions, 0);
      expect(engine.stats.streakDays, 0);
      engine.dispose();
    });
  });

  group('tutorSay (조교 메시지)', () {
    test('히스토리에 추가되고 저장된다', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);

      final m = engine.tutorSay('오늘의 문제: 일차방정식이 뭘까?');

      expect(m.role, 'assistant');
      expect(engine.history.single.content, '오늘의 문제: 일차방정식이 뭘까?');

      await engine.flush();
      final restored = TikiTakaLfm(client: client);
      await restored.loadHistory();
      expect(restored.history.single.content, '오늘의 문제: 일차방정식이 뭘까?');
      engine.dispose();
      restored.dispose();
    });

    test('활동 통계에 영향을 주지 않는다', () async {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.tutorSay('문제');
      engine.tutorSay('다른 문제');
      expect(engine.stats.totalQuestions, 0);
      expect(engine.stats.streakDays, 0);
      engine.dispose();
    });

    test('이후 ask 컨텍스트에 포함된다', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('ok'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.tutorSay('질문: 2+2는?');
      await engine.ask('4');
      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages.any((m) =>
          m is Map && m['content'] == '질문: 2+2는?'), isTrue);
      engine.dispose();
    });
  });

  group('과목별 분리 (multi-subject)', () {
    test('과목별 히스토리·통계가 분리되어 저장된다', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);

      engine.setSubject('수학');
      await engine.ask('수학 질문');
      await engine.flush();

      engine.setSubject('영어');
      await engine.ask('영어 질문');
      await engine.flush();

      // 새 엔진으로 과목별 복원 확인
      final math = TikiTakaLfm(client: client);
      math.setSubject('수학');
      await math.loadHistory();
      expect(math.history.first.content, '수학 질문');
      expect(math.history, hasLength(2));
      expect(math.stats.totalQuestions, 1);

      final eng = TikiTakaLfm(client: client);
      eng.setSubject('영어');
      await eng.loadHistory();
      expect(eng.history.first.content, '영어 질문');
      expect(eng.history, hasLength(2));
      expect(eng.stats.totalQuestions, 1);

      engine.dispose();
      math.dispose();
      eng.dispose();
    });

    test('주제 전환 시 대기 중인 저장이 유실되지 않는다', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(
          client: client, saveDebounce: const Duration(minutes: 1));

      engine.setSubject('수학');
      await engine.ask('유실되면 안 되는 질문');
      // 디바운스 저장이 실행되기 전에 주제 전환 → 대기 스냅샷이 수학 키로 쓰여야 함
      engine.setSubject('영어');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final restored = TikiTakaLfm(client: client);
      restored.setSubject('수학');
      await restored.loadHistory();
      expect(restored.history.first.content, '유실되면 안 되는 질문');
      engine.dispose();
      restored.dispose();
    });

    test('과목 전환 후 새 과목 통계는 0부터 시작', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('1');
      await engine.flush();
      expect(engine.stats.totalQuestions, 1);

      engine.setSubject('영어');
      expect(engine.stats.totalQuestions, 0);
      expect(engine.stats.streakDays, 0);

      engine.setSubject('수학');
      await engine.loadHistory();
      expect(engine.stats.totalQuestions, 1); // 저장된 수학 통계 복원
      engine.dispose();
    });
  });

  group('allStats (과목 전체 통계)', () {
    test('저장된 모든 과목의 통계를 반환', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('1');
      await engine.flush();
      engine.setSubject('영어');
      await engine.ask('2');
      await engine.flush();

      final all = await engine.allStats();
      expect(all.keys.toSet(), {'수학', '영어'});
      expect(all['수학']!.totalQuestions, 1);
      expect(all['영어']!.totalQuestions, 1);
      engine.dispose();
    });

    test('현재 주제의 메모리 통계가 최신으로 반영된다 (저장 전)', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('1'); // 디바운스로 아직 저장 전

      final all = await engine.allStats();
      expect(all['수학']!.totalQuestions, 1);
      engine.dispose();
    });

    test('기본 주제는 빈 키로 취급된다', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      await engine.ask('기본 주제 질문');
      await engine.flush();

      final all = await engine.allStats();
      expect(all.containsKey(''), isTrue);
      expect(all['']!.totalQuestions, 1);
      engine.dispose();
    });
  });

  group('exportHistory (마크다운 내보내기)', () {
    test('과목·통계·Q&A를 마크다운으로 내보낸다', () async {
      final client = _mock((req) => _chatReply('근의 공식이야!'));
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('이차방정식 풀이는?');

      final md = engine.exportHistory();
      expect(md, contains('# 학습 기록 — 수학'));
      expect(md, contains('**Q:** 이차방정식 풀이는?'));
      expect(md, contains('**A:** 근의 공식이야!'));
      expect(md, contains('💬 1개 질문'));
      // 날짜 섹션 (오늘 날짜)
      final today = DateTime.now();
      final day = '${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      expect(md, contains('## $day'));
      engine.dispose();
    });

    test('빈 기록이면 안내 문구를 포함한다', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.setSubject('영어');
      final md = engine.exportHistory();
      expect(md, contains('# 학습 기록 — 영어'));
      expect(md, contains('아직 대화 기록이 없습니다'));
      engine.dispose();
    });
  });

  group('summarize (AI 학습 요약)', () {
    test('빈 기록이면 HTTP 호출 없이 빈 문자열', () async {
      final log = <http.Request>[];
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('x'), log: log));
      expect(await engine.summarize(), '');
      expect(log, isEmpty);
      engine.dispose();
    });

    test('최근 대화를 중립 프롬프트로 요약하고 히스토리를 건드리지 않는다', () async {
      final log = <http.Request>[];
      final client = _mock((req) => _chatReply('요약: 이차방정식'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('이차방정식이 뭐야?');
      final before = engine.history.length;

      final summary = await engine.summarize(maxLines: 2);

      expect(summary, '요약: 이차방정식');
      // 히스토리 비파괴
      expect(engine.history.length, before);
      // 요청 본문: 중립 시스템 프롬프트 + 대화 대본 + 줄 수 제한
      final body = jsonDecode(log.last.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect((messages.first['content'] as String), contains('요약하는 조수'));
      expect((messages.last['content'] as String), contains('2줄'));
      expect((messages.last['content'] as String), contains('이차방정식이 뭐야?'));
      engine.dispose();
    });

    test('빈 요약 응답이면 FormatException', () async {
      final log = <http.Request>[];
      // 첫 요청(ask)은 정상, 두 번째 요청(summarize)은 빈 응답
      final client = _mock((req) {
        if (log.length == 1) return _chatReply('정상 답변');
        return streamReply([], done: true);
      }, log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('질문');
      await expectLater(engine.summarize(), throwsA(isA<FormatException>()));
      engine.dispose();
    });
  });

  group('learningPlan (맞춤 학습 계획)', () {
    test('주제·통계·최근 대화를 반영한 계획을 요청한다', () async {
      final log = <http.Request>[];
      final client = _mock(
          (req) => _chatReply('1) 개념 복습 2) 문제 풀이'), log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('이차방정식이 뭐야?');
      final before = engine.history.length;

      final plan = await engine.learningPlan(minutes: 5);

      expect(plan, contains('복습'));
      expect(engine.history.length, before); // 히스토리 비파괴
      final body = jsonDecode(log.last.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect((messages.first['content'] as String), contains('학습 코치'));
      final prompt = messages.last['content'] as String;
      expect(prompt, contains('수학'));
      expect(prompt, contains('5분'));
      expect(prompt, contains('이차방정식이 뭐야?'));
      engine.dispose();
    });

    test('빈 계획 응답이면 FormatException', () async {
      final log = <http.Request>[];
      final client = _mock((req) {
        if (log.length == 1) return _chatReply('정상 답변');
        return streamReply([], done: true);
      }, log: log);
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      await engine.ask('질문');
      await expectLater(
          engine.learningPlan(), throwsA(isA<FormatException>()));
      engine.dispose();
    });
  });

  group('오답노트 (mistake book)', () {
    test('항목 추가·조회·삭제·비우기', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.addMistake('이차방정식이 뭐야?', '근의 공식',
          note: 'b²-4ac 부호 주의');
      engine.addMistake('피타고라스 정리는?', 'a²+b²=c²');

      expect(engine.mistakes, hasLength(2));
      expect(engine.mistakes.first.question, '이차방정식이 뭐야?');
      expect(engine.mistakes.first.note, 'b²-4ac 부호 주의');

      engine.removeMistake(0);
      expect(engine.mistakes.single.question, '피타고라스 정리는?');

      engine.clearMistakes();
      expect(engine.mistakes, isEmpty);
      engine.dispose();
    });

    test('과목별로 분리 저장·복원된다', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('수학');
      engine.addMistake('수학 오답', '정답');
      await engine.flush();

      engine.setSubject('영어');
      engine.addMistake('영어 오답', 'answer');
      await engine.flush();
      expect(engine.mistakes, hasLength(1));

      // 수학 복원
      final math = TikiTakaLfm(client: client);
      math.setSubject('수학');
      await math.loadHistory();
      expect(math.mistakes.single.question, '수학 오답');
      engine.dispose();
      math.dispose();
    });

    test('내보내기에 오답노트 섹션이 포함된다', () async {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.setSubject('과학');
      engine.addMistake('광합성 장소는?', '엽록체');
      final md = engine.exportHistory();
      expect(md, contains('## 오답 노트'));
      expect(md, contains('1. **Q:** 광합성 장소는?'));
      expect(md, contains('**A:** 엽록체'));
      engine.dispose();
    });

    test('reset은 오답노트를 초기화한다', () async {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.addMistake('문제', '답');
      await engine.reset();
      expect(engine.mistakes, isEmpty);
      engine.dispose();
    });

    test('복습: 오답노트를 순환하며 다음 항목을 반환', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.addMistake('문제1', '답1');
      engine.addMistake('문제2', '답2');

      final first = engine.nextMistakeReview();
      final second = engine.nextMistakeReview();
      final third = engine.nextMistakeReview(); // 순환 → 다시 첫 항목

      expect(first!.question, '문제1');
      expect(second!.question, '문제2');
      expect(third!.question, '문제1');
      engine.dispose();
    });

    test('복습: 오답노트가 비어 있으면 null', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      expect(engine.nextMistakeReview(), isNull);
      engine.dispose();
    });

    test('복습: 맞았어요로 삭제하면 순환이 처음부터', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.addMistake('문제1', '답1');
      engine.addMistake('문제2', '답2');

      final first = engine.nextMistakeReview(); // 문제1
      engine.removeMistake(engine.mistakes.indexOf(first!)); // 문제1 삭제

      final next = engine.nextMistakeReview();
      expect(next!.question, '문제2'); // 삭제 후 인덱스 리셋 → 처음부터
      engine.dispose();
    });
  });

  group('일별 활동 (weekly activity)', () {
    test('활동한 날에 질문 수가 누적된다', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('1');
      await engine.ask('2');
      await engine.ask('3');

      final weekly = engine.weeklyActivity;
      expect(weekly['2026-08-14'], 3);
      // 7일 중 나머지는 0
      expect(weekly, hasLength(7));
      expect(weekly.values.where((v) => v > 0).length, 1);
      engine.dispose();
    });

    test('날짜가 바뀌면 새 항목이 생기고 주간 집계에 반영된다', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('1일차');
      now = DateTime(2026, 8, 16, 9, 0);
      await engine.ask('3일차');

      final weekly = engine.weeklyActivity;
      expect(weekly['2026-08-14'], 1);
      expect(weekly['2026-08-15'], 0);
      expect(weekly['2026-08-16'], 1);
      engine.dispose();
    });

    test('영속화: flush 후 새 엔진에서 복원된다', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client, clock: () => now);
      await engine.ask('1');
      await engine.flush();

      final restored = TikiTakaLfm(client: client, clock: () => now);
      await restored.loadHistory();
      expect(restored.weeklyActivity['2026-08-14'], 1);
      engine.dispose();
      restored.dispose();
    });

    test('reset은 일별 활동을 초기화한다', () async {
      var now = DateTime(2026, 8, 14, 10, 0);
      final engine = TikiTakaLfm(
          client: _mock((req) => _chatReply('ok')), clock: () => now);
      await engine.ask('1');
      await engine.reset();
      expect(engine.weeklyActivity.values.every((v) => v == 0), isTrue);
      engine.dispose();
    });
  });

  group('프로액티브 학습 타이머', () {
    test('onTick 콜백이 주기적으로 호출되고 stop 시 중단', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      engine.setSubject('역사');

      var ticks = 0;
      String? lastGreeting;
      engine.startProactiveLearning(
        interval: const Duration(milliseconds: 10),
        onTick: (g) {
          ticks++;
          lastGreeting = g;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 45));
      engine.stopProactiveLearning();
      final ticksBefore = ticks;

      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(ticks, ticksBefore); // stop 이후 증가 없음
      expect(ticks, greaterThan(0));
      expect(lastGreeting, contains('역사'));
      engine.dispose();
    });
  });

  group('히스토리 뷰', () {
    test('history는 수정 불가능한 뷰', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      expect(
        () => engine.history.add(TkMessage(role: 'user', content: 'x')),
        throwsUnsupportedError,
      );
      engine.dispose();
    });
  });
}
