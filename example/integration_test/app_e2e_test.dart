import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tikitaka_example/main.dart';

/// 에뮬레이터/실기기 위 실제 Ollama 연동 E2E 테스트.
///
/// 실행:
///   adb reverse tcp:11434 tcp:11434   # 에뮬레이터 localhost → 호스트 Ollama
///   flutter test integration_test -d `device`
///
/// 호스트는 기본값(127.0.0.1)을 유지하고, 호스트 Ollama에 있는 모델로만
/// 변경해 연결 → 대화까지 검증한다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 120),
    VoidCallback? onTick,
  }) async {
    final end = DateTime.now().add(timeout);
    var lastTick = DateTime.now();
    while (DateTime.now().isBefore(end)) {
      if (condition()) return;
      if (onTick != null && DateTime.now().difference(lastTick) >=
          const Duration(seconds: 15)) {
        lastTick = DateTime.now();
        onTick();
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
    throw TimeoutException('조건이 시간 내에 충족되지 않음');
  }

  testWidgets('설정 변경 → Ollama 연결 → AI 응답 (E2E)', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pumpAndSettle();

    // 1) 설정 열기
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Ollama 연결 설정'), findsOneWidget);

    // 2) 모델만 호스트 Ollama에 있는 모델로 변경 (호스트는 127.0.0.1 기본값 —
    //    adb reverse tcp:11434로 에뮬레이터 localhost → 호스트 Ollama 라우팅)
    await tester.enterText(
        find.widgetWithText(TextField, '모델'), 'lfm2.5:2.6b-64k');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    // 3) 연결 상태 대기 (isAvailable이 실제 호스트 Ollama를 확인)
    await waitUntil(
      tester,
      () => find.textContaining('연결됨').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    expect(find.textContaining('연결됨'), findsOneWidget);

    // 4) 질문 전송
    await tester.enterText(
        find.byType(TextField).last, 'what is 2+2? answer briefly');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // 5) 스트리밍 완료 대기 (전송 버튼이 다시 활성화될 때까지)
    await waitUntil(
      tester,
      () {
        final senders = tester
            .widgetList<IconButton>(find.ancestor(
                of: find.byIcon(Icons.send),
                matching: find.byType(IconButton)))
            .toList();
        return senders.isNotEmpty && senders.last.onPressed != null;
      },
      timeout: const Duration(seconds: 360),
      onTick: () {
        final texts = tester
            .widgetList<Text>(find.descendant(
                of: find.byType(ListView), matching: find.byType(Text)))
            .map((t) => t.data ?? '')
            .where((t) => t.isNotEmpty)
            .toList();
        debugPrint(
            '[E2E] 대기 중... 마지막 메시지: ${texts.isEmpty ? "없음" : texts.last}');
      },
    );

    // 6) 응답에 정답(4)이 포함되어 있는지
    await waitUntil(
      tester,
      () => find.textContaining('4').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );
    expect(find.textContaining('4'), findsWidgets);
  });
}
