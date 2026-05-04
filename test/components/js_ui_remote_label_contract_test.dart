import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/js_ui.dart';
import 'package:venera/utils/opencc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await OpenCC.init();
  });

  test(
    'zh_HK select display label converts while option value contract stays raw',
    () {
      const rawValue = 'language';
      const rawDisplay = '语言';

      final display = normalizeJsSelectOptionLabelForDisplay(
        rawDisplay,
        const Locale('zh', 'HK'),
      );

      expect(display, '語言');
      expect(rawValue, 'language');
    },
  );
}
