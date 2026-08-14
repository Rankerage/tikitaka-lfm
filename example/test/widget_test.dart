import 'package:flutter/material.dart';
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
}
