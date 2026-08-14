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
}
