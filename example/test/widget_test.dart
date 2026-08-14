import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tikitaka_example/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('앱이 실행되면 주제 칩과 채팅 UI가 보인다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    // 앱바 타이틀
    expect(find.text('🎯 TikiTaka'), findsOneWidget);
    // 주제 칩
    expect(find.text('수학'), findsWidgets);
    expect(find.text('영어'), findsOneWidget);
    // 설정 버튼
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('설정 시트를 열면 Ollama 설정 필드가 보인다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Ollama 연결 설정'), findsOneWidget);
    expect(find.text('호스트'), findsOneWidget);
    expect(find.text('모델'), findsOneWidget);
  });

  testWidgets('채팅 상태바에 연결 다시 확인 버튼이 있다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    expect(find.byIcon(Icons.refresh), findsOneWidget);

    // 테스트 환경 HTTP는 항상 400 → 오프라인 유지, 크래시 없어야 함
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('오프라인'), findsOneWidget);
  });

  testWidgets('학습 통계 표시줄이 보인다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    expect(find.textContaining('일 연속'), findsOneWidget);
    expect(find.textContaining('최고'), findsOneWidget);
    expect(find.textContaining('질문'), findsOneWidget);
  });

  testWidgets('직접 입력으로 새 주제를 추가할 수 있다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.text('직접 입력'));
    await tester.pumpAndSettle();
    expect(find.text('새 학습 주제'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '물리');
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    // 새 주제 칩 + 채팅 상태바 주제 라벨에 나타난다
    expect(find.text('물리'), findsWidgets);
  });

  testWidgets('리셋 버튼은 확인 대화상자를 거친다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_sweep));
    await tester.pumpAndSettle();
    expect(find.text('학습 기록 초기화'), findsOneWidget);

    // 초기화 확인 후 크래시 없이 동작
    await tester.tap(find.text('초기화'));
    await tester.pumpAndSettle();
    expect(find.textContaining('일 연속'), findsOneWidget);
  });

  testWidgets('문제 버튼으로 퀴즈가 표시된다 (오프라인에서도 동작)', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    // 초기에는 퀴즈 메시지 없음
    expect(find.textContaining('어려웠던 개념'), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, '문제'));
    await tester.pump();

    // makeQuiz() 템플릿이 대화에 표시된다
    expect(find.textContaining('어려웠던 개념'), findsOneWidget);
  });

  testWidgets('평가 버튼은 사용자 메시지가 없으면 비활성', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    final chip = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, '평가'),
    );
    expect(chip.onPressed, isNull);

    // 비활성 상태에서 탭해도 크래시 없음
    await tester.tap(find.widgetWithText(ActionChip, '평가'),
        warnIfMissed: false);
    await tester.pump();
  });

  testWidgets('통계 화면에 과목별 streak이 표시된다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    expect(find.text('학습 통계'), findsOneWidget);
    expect(find.textContaining('일 연속'), findsWidgets);
    // 현재 과목(수학) 행
    expect(find.text('수학'), findsOneWidget);
    // 뒤로가기로 홈 복귀
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('🎯 TikiTaka'), findsOneWidget);
  });

  testWidgets('통계 화면에서 기록을 클립보드로 내보낼 수 있다', (tester) async {
    final clipboardCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        clipboardCalls.add(call);
        return null;
      },
    );

    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.copy_all));
    await tester.pumpAndSettle();

    final setData = clipboardCalls.where(
        (c) => c.method == 'Clipboard.setData');
    expect(setData, isNotEmpty);
    final args = setData.first.arguments as Map;
    expect((args['text'] as String), contains('# 학습 기록'));
  });

  testWidgets('통계 화면에서 AI 요약을 시도하면 빈 기록 안내가 나온다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.summarize));
    await tester.pumpAndSettle();

    // 기록이 없으므로 HTTP 호출 없이 안내 스낵바
    expect(find.textContaining('기록이 없습니다'), findsOneWidget);
  });

  testWidgets('계획 버튼은 오프라인에서 오류를 안전하게 처리한다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    // 테스트 환경 HTTP는 항상 400 → 학습 계획 생성 실패 버블
    await tester.tap(find.widgetWithText(ActionChip, '계획'));
    await tester.pumpAndSettle();
    expect(find.textContaining('학습 계획 생성 실패'), findsOneWidget);
  });

  testWidgets('앱 정보 다이얼로그가 버전을 표시한다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('TikiTaka'), findsWidgets);
    expect(find.textContaining(kAppVersion), findsWidgets);
    expect(find.textContaining('lfm2.5-thinking'), findsOneWidget);
  });

  testWidgets('오답 버튼은 사용자 메시지가 없으면 비활성', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    final chip = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, '오답'),
    );
    expect(chip.onPressed, isNull);
  });

  testWidgets('통계 화면에 오답노트 빈 상태가 보인다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    expect(find.textContaining('오답노트가 비어 있습니다'), findsOneWidget);
    expect(find.textContaining('오답노트'), findsWidgets);
  });

  testWidgets('복습 모드는 오답노트가 비어 있으면 안내 후 닫힌다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    await tester.tap(find.text('복습'));
    await tester.pumpAndSettle();

    expect(find.text('오답노트 복습'), findsOneWidget);
    expect(find.text('오답노트가 비어 있습니다'), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('학습 통계'), findsOneWidget);
  });

  testWidgets('통계 화면에 최근 7일 활동 그래프가 보인다', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    expect(find.text('최근 7일 활동'), findsOneWidget);
    // 활동이 없으면 7일 모두 0으로 표시
    expect(find.text('0'), findsNWidgets(7));
  });

  testWidgets('설정에 학습 알림 스위치가 있다 (토글해도 크래시 없음)', (tester) async {
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('학습 알림 (매일)'), findsOneWidget);

    // 테스트 환경(플랫폼 채널 없음)에서 토글 → 실패 스낵바 또는 상태 유지, 크래시 없음
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
