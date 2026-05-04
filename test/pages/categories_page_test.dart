import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/pages/categories_page.dart';
import 'package:venera/utils/opencc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const settingKey = 'enableRemoteChineseTextConversion';
  setUpAll(() async {
    await OpenCC.init();
  });

  test('category display label normalizes under zh_HK when enabled', () {
    appdata.settings[settingKey] = true;
    appdata.settings['language'] = 'zh-TW';
    expect(normalizeCategoryDisplayLabel('语言'), '語言');
  });

  test('category display label unchanged when setting disabled', () {
    appdata.settings[settingKey] = false;
    appdata.settings['language'] = 'zh-TW';
    expect(normalizeCategoryDisplayLabel('语言'), '语言');
  });
}
