import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// flutter drive용 드라이버 — onScreenshot으로 스크린샷을 저장한다.
///
/// 실행: flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/screenshots_test.dart -d <device>
Future<void> main() {
  return integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
