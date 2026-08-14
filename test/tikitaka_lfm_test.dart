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
    test('저장된 기록 복원', () async {
      final client = _mock((req) => _chatReply('ok'));
      final engine = TikiTakaLfm(client: client);
      await engine.ask('첫 질문');
      // 새 엔진으로 복원
      final engine2 = TikiTakaLfm(client: client);
      await engine2.loadHistory();
      expect(engine2.history, hasLength(2));
      expect(engine2.history.first.content, '첫 질문');
      engine.dispose();
      engine2.dispose();
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
    test('makeQuiz는 템플릿을 순환', () {
      final engine = TikiTakaLfm(client: _mock((req) => _chatReply('ok')));
      engine.setSubject('영어');
      final q1 = engine.makeQuiz();
      final q2 = engine.makeQuiz();
      final q3 = engine.makeQuiz();
      final q4 = engine.makeQuiz();
      expect(q1, contains('영어'));
      expect(q1, isNot(equals(q2)));
      expect(q1, isNot(equals(q3)));
      expect(q1, equals(q4)); // 3개 템플릿 순환
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
