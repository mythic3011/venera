import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart' as diag;
import 'package:venera/utils/opencc.dart';
import 'package:venera/utils/remote_text_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const settingKey = 'enableRemoteChineseTextConversion';

  setUpAll(() async {
    await OpenCC.init();
  });

  setUp(() {
    diag.AppDiagnostics.configureSinksForTesting(const []);
    appdata.settings[settingKey] = true;
  });

  tearDown(() {
    diag.AppDiagnostics.resetForTesting();
    appdata.settings[settingKey] = true;
  });

  test('zh_HK enabled converts simplified to traditional', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '语言',
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('zh', 'HK'),
        enabled: true,
      ),
      '語言',
    );
  });

  test('zh_TW enabled converts simplified to traditional', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '语言',
        surface: RemoteTextSurface.categoryLabel,
        locale: const Locale('zh', 'TW'),
        enabled: true,
      ),
      '語言',
    );
  });

  test('zh_CN enabled converts traditional to simplified', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '語言',
        surface: RemoteTextSurface.commandLabel,
        locale: const Locale('zh', 'CN'),
        enabled: true,
      ),
      '语言',
    );
  });

  test('zh_Hans enabled converts traditional to simplified', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '語言',
        surface: RemoteTextSurface.commandLabel,
        locale: const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        ),
        enabled: true,
      ),
      '语言',
    );
  });

  test('en_US unchanged', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '语言',
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('en', 'US'),
        enabled: true,
      ),
      '语言',
    );
  });

  test('disabled unchanged', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '语言',
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('zh', 'HK'),
        enabled: false,
      ),
      '语言',
    );
  });

  test('zh_HK with null enabled follows app setting', () {
    appdata.settings[settingKey] = false;
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '语言',
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('zh', 'HK'),
      ),
      '语言',
    );
    appdata.settings[settingKey] = true;
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '语言',
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('zh', 'HK'),
      ),
      '語言',
    );
  });

  test('戀愛/校園 is not blocked by path guard', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        '戀愛/校園',
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('zh', 'CN'),
        enabled: true,
      ),
      '恋爱/校园',
    );
  });

  test('URL path and code-ish strings unchanged', () {
    const locale = Locale('zh', 'HK');
    expect(
      RemoteTextNormalizer.normalizeLabel(
        'https://example.com/语言',
        surface: RemoteTextSurface.tagLabel,
        locale: locale,
        enabled: true,
      ),
      'https://example.com/语言',
    );
    expect(
      RemoteTextNormalizer.normalizeLabel(
        r'C:\work\语言',
        surface: RemoteTextSurface.tagLabel,
        locale: locale,
        enabled: true,
      ),
      r'C:\work\语言',
    );
    expect(
      RemoteTextNormalizer.normalizeLabel(
        'document.querySelector(".语言")',
        surface: RemoteTextSurface.tagLabel,
        locale: locale,
        enabled: true,
      ),
      'document.querySelector(".语言")',
    );
  });

  test('mixed Chinese/ASCII keeps structure and converts Chinese only', () {
    expect(
      RemoteTextNormalizer.normalizeLabel(
        'Language-语言-v2',
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('zh', 'HK'),
        enabled: true,
      ),
      'Language-語言-v2',
    );
  });

  test(
    'throwing converter returns original and emits warn without raw label',
    () {
      final original = '语言-ABC';
      final normalized = RemoteTextNormalizer.normalizeLabel(
        original,
        surface: RemoteTextSurface.tagLabel,
        locale: const Locale('zh', 'HK'),
        enabled: true,
        s2t: (_) => throw StateError('boom'),
      );

      expect(normalized, original);
      final events = diag.DevDiagnosticsApi.recent(
        minLevel: diag.DiagnosticLevel.warn,
      );
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.channel, 'text.normalization');
      expect(event.message, 'text.normalization.failed');
      expect(event.data['direction'], 'toTraditional');
      expect((event.data['inputLength'] as int) > 0, isTrue);
      expect(event.data.toString().contains(original), isFalse);
    },
  );
}
