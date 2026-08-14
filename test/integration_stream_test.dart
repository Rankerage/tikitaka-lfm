@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tikitaka_lfm/tikitaka_lfm.dart';

/// 실제 Ollama 서버를 대상으로 한 통합 테스트.
///
/// - 환경변수로 대상 설정 가능: OLLAMA_HOST(기본 127.0.0.1),
///   OLLAMA_PORT(기본 11434), TIKITAKA_MODEL(기본 lfm2.5-thinking:1.2b)
/// - Ollama가 실행 중이 아니거나 모델이 없으면 그룹 전체가 자동 skip된다.
/// - 실행: flutter test test/integration_stream_test.dart
void main() {
  // 주의: TestWidgetsFlutterBinding.ensureInitialized()를 호출하면 flutter_test의
  // HTTP 모킹(모든 요청 400)이 활성화되어 실제 Ollama에 접속할 수 없다.
  // SharedPreferences만 메모리 mock으로 대체한다.
  SharedPreferences.setMockInitialValues({});

  final host = Platform.environment['OLLAMA_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['OLLAMA_PORT'] ?? '') ?? 11434;
  final model = Platform.environment['TIKITAKA_MODEL'] ?? 'lfm2.5-thinking:1.2b';

  late final TikiTakaLfm engine;

  setUpAll(() {
    // 테스트 존 안에서 생성해야 http.Client()가 정상 동작
    engine = TikiTakaLfm(
      config: LfmConfig(host: host, port: port, model: model),
    );
  });

  tearDownAll(() => engine.dispose());

  test('실제 모델과 스트리밍 대화', () async {
    if (!await engine.isAvailable()) {
      markTestSkipped(
          'Ollama($host:$port)에 $model 모델이 없어 통합 테스트를 건너뜁니다.');
      return;
    }
    engine.setSubject('수학');

    final deltas = <String>[];
    await for (final d in engine.askStream('1+1은? 답만 짧게 말해줘')) {
      deltas.add(d);
    }

    // 토큰 단위 델타가 실제로 내려왔는지 (LLM 답변 내용은 검증하지 않음)
    expect(deltas, isNotEmpty);
    final full = deltas.join();
    expect(full.trim(), isNotEmpty);

    // 히스토리 저장 확인
    expect(engine.history, hasLength(2));
    expect(engine.history.last.role, 'assistant');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('실제 모델로 학습 요약 생성', () async {
    if (!await engine.isAvailable()) {
      markTestSkipped(
          'Ollama($host:$port)에 $model 모델이 없어 통합 테스트를 건너뜁니다.');
      return;
    }
    // 대화를 하나 만든 뒤 요약
    final before = engine.history.length;
    await for (final _ in engine.askStream('1+1은? 답만 짧게 말해줘')) {}
    expect(engine.history.length, before + 2);
    final summary = await engine.summarize(maxLines: 2);
    expect(summary.trim(), isNotEmpty);
    // 요약은 히스토리에 남지 않는다
    expect(engine.history.length, before + 2);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('실제 모델로 맞춤 학습 계획 생성', () async {
    if (!await engine.isAvailable()) {
      markTestSkipped(
          'Ollama($host:$port)에 $model 모델이 없어 통합 테스트를 건너뜁니다.');
      return;
    }
    final before = engine.history.length;
    final plan = await engine.learningPlan(minutes: 5);
    expect(plan.trim(), isNotEmpty);
    // 계획은 히스토리에 남지 않는다
    expect(engine.history.length, before);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
