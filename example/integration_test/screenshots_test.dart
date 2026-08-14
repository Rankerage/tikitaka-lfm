import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tikitaka_example/main.dart';

/// 앱 스토어 리스팅용 스크린샷 캡처.
///
/// 실행(드라이버 경유): flutter drive --driver=test_driver/integration_test.dart
///   --target=integration_test/screenshots_test.dart -d `device`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('주요 화면 스크린샷 캡처', (tester) async {
    // Android에서 스크린샷을 찍으려면 FlutterSurface를 이미지로 전환해야 한다
    await binding.convertFlutterSurfaceToImage();

    // 홈 — 채팅
    await tester.pumpWidget(const TikiTakaApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await binding.takeScreenshot('01_home_chat');

    // 통계 화면
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02_stats');

    // 오답노트 복습 (빈 상태)
    await tester.tap(find.text('복습'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03_review_empty');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 설정 시트
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04_settings');

    // 모달 시트는 뒤로가기 버튼이 없으므로 바깥(배리어)을 탭해 닫는다
    await tester.tapAt(const Offset(400, 50));
    await tester.pumpAndSettle();

    // 앱 정보 다이얼로그
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05_about');
  });
}
