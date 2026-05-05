import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/diagnostics/log_export_bundle.dart';

void main() {
  late bool oldInitialized;
  late String? oldDataPath;
  late String? oldExternal;

  setUp(() {
    oldInitialized = App.isInitialized;
    oldDataPath = oldInitialized ? App.dataPath : null;
    oldExternal = App.externalStoragePath;
    AppDiagnostics.resetForTesting();
  });

  tearDown(() {
    if (oldInitialized && oldDataPath != null) {
      App.dataPath = oldDataPath!;
    }
    App.externalStoragePath = oldExternal;
    App.isInitialized = oldInitialized;
    AppDiagnostics.resetForTesting();
  });

  test(
    'crash report bundle excludes DB/cookie files and raw SQL params',
    () async {
      final dir = await Directory.systemTemp.createTemp('venera_crash_bundle_');
      App.dataPath = dir.path;
      App.externalStoragePath = dir.path;
      App.isInitialized = true;

      final marker = File('${dir.path}/runtime/lifecycle_marker.json');
      await marker.parent.create(recursive: true);
      await marker.writeAsString(
        jsonEncode({
          'pid': 42,
          'startedAt': '2026-05-01T00:00:00Z',
          'fatal': {'classification': 'app.fatal.dbLocked'},
          'runtimeRoot': dir.path,
        }),
      );

      AppDiagnostics.error(
        'app.fatal',
        StateError('SELECT * FROM users WHERE token=abc password=secret'),
        message: 'app.fatal.dbLocked',
        data: {
          'sqliteCode': 5,
          'query': 'SELECT * FROM users WHERE password=?',
          'cookie': 'session=abc',
        },
      );

      final file = await exportCrashReportBundleToFile();
      expect(file, isNotNull);
      final content = await file!.readAsString();

      expect(
        content.contains('=== Previous Lifecycle Marker (JSON) ==='),
        isTrue,
      );
      expect(content.contains('=== DB Lock Summary (JSON) ==='), isTrue);
      expect(content.contains('token=abc'), isFalse);
      expect(content.contains('password=secret'), isFalse);
      expect(content.contains('session=abc'), isFalse);
      expect(content.contains('cookies.sqlite'), isFalse);

      await dir.delete(recursive: true);
    },
  );
}
