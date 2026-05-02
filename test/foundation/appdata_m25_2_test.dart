import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  Future<void> mockPathProvider(Directory dir) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory' ||
              call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getApplicationCacheDirectory') {
            return dir.path;
          }
          return dir.path;
        });
  }

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('missing appdata json does not crash startup and persists defaults', () async {
    final tempDir = await Directory.systemTemp.createTemp('appdata-m25-2-missing-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);

    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    addTearDown(store.close);

    App.dataPath = tempDir.path;
    final sut = Appdata.createForTest(settingsStore: store);

    await sut.doInit();

    expect((sut.settings['deviceId'] as String).isNotEmpty, isTrue);
    final rows = await store.loadAppSettings();
    expect(rows, isNotEmpty);
  });

  test('corrupt appdata json does not wipe existing db settings', () async {
    final tempDir = await Directory.systemTemp.createTemp('appdata-m25-2-corrupt-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);

    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    addTearDown(store.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.upsertAppSetting(
      AppSettingRecord(
        key: 'deviceId',
        valueJson: jsonEncode('fixed-device-id'),
        valueType: 'string',
        syncPolicy: 'local_only',
        updatedAtMs: now,
      ),
    );
    await store.upsertAppSetting(
      AppSettingRecord(
        key: 'reader_next_enabled',
        valueJson: jsonEncode(false),
        valueType: 'bool',
        syncPolicy: 'syncable',
        updatedAtMs: now,
      ),
    );
    await File(p.join(tempDir.path, 'appdata.json')).writeAsString('{bad-json');

    App.dataPath = tempDir.path;
    final sut = Appdata.createForTest(settingsStore: store);

    await sut.doInit();

    expect(sut.settings['deviceId'], 'fixed-device-id');
    expect(sut.settings['reader_next_enabled'], false);
  });

  test('migration is idempotent across repeated init', () async {
    final tempDir = await Directory.systemTemp.createTemp('appdata-m25-2-idempotent-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);

    final legacyJson = {
      'settings': {
        'deviceId': 'legacy-device-id',
        'reader_next_enabled': false,
      },
      'searchHistory': ['foo', 'bar'],
    };
    await File(
      p.join(tempDir.path, 'appdata.json'),
    ).writeAsString(jsonEncode(legacyJson));
    await File(
      p.join(tempDir.path, 'implicitData.json'),
    ).writeAsString(jsonEncode({'last_opened': 'comic-1'}));

    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    addTearDown(store.close);
    App.dataPath = tempDir.path;

    final first = Appdata.createForTest(settingsStore: store);
    await first.doInit();
    final firstSettings = await store.loadAppSettings();
    final firstHistory = await store.loadSearchHistory();
    final firstImplicit = await store.loadImplicitData();

    final second = Appdata.createForTest(settingsStore: store);
    await second.doInit();
    final secondSettings = await store.loadAppSettings();
    final secondHistory = await store.loadSearchHistory();
    final secondImplicit = await store.loadImplicitData();

    expect(secondSettings.length, firstSettings.length);
    expect(
      secondSettings
          .firstWhere((row) => row.key == 'deviceId')
          .valueJson,
      jsonEncode('legacy-device-id'),
    );
    expect(secondHistory.map((row) => row.keyword).toList(), ['foo', 'bar']);
    expect(secondHistory.length, firstHistory.length);
    expect(secondImplicit.length, firstImplicit.length);
  });

  test('saveData keeps disableSyncFields semantics unchanged', () async {
    final tempDir = await Directory.systemTemp.createTemp('appdata-m25-2-sync-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);

    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    addTearDown(store.close);

    App.dataPath = tempDir.path;
    final sut = Appdata.createForTest(settingsStore: store);
    sut.settings['deviceId'] = 'device-for-sync';
    sut.settings['reader_next_history_enabled'] = false;
    sut.settings['disableSyncFields'] = 'reader_next_history_enabled';

    await sut.saveData(false);

    final syncFile = File(p.join(tempDir.path, 'syncdata.json'));
    expect(syncFile.existsSync(), isTrue);
    final syncJson = jsonDecode(await syncFile.readAsString()) as Map<String, dynamic>;
    final syncSettings = syncJson['settings'] as Map<String, dynamic>;
    expect(syncSettings.containsKey('reader_next_history_enabled'), isFalse);
  });

  test('legacy migration writes one-time backup file', () async {
    final tempDir = await Directory.systemTemp.createTemp('appdata-m25-2-backup-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);

    final legacyFile = File(p.join(tempDir.path, 'appdata.json'));
    await legacyFile.writeAsString(
      jsonEncode({
        'settings': {'deviceId': 'legacy-device-id'},
        'searchHistory': <String>[],
      }),
    );

    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    addTearDown(store.close);
    App.dataPath = tempDir.path;

    final sut = Appdata.createForTest(settingsStore: store);
    await sut.doInit();

    final backupFile = File('${legacyFile.path}.m25_2_backup');
    expect(backupFile.existsSync(), isTrue);
    expect(await backupFile.readAsString(), await legacyFile.readAsString());
  });

  test('map-valued settings remain map after db migration/load', () async {
    final tempDir = await Directory.systemTemp.createTemp('appdata-m25-2-map-shape-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);

    final legacyJson = {
      'settings': {
        'dnsOverrides': {'api': 'api.copy2000.online'},
      },
      'searchHistory': <String>[],
    };
    await File(
      p.join(tempDir.path, 'appdata.json'),
    ).writeAsString(jsonEncode(legacyJson));

    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    addTearDown(store.close);
    App.dataPath = tempDir.path;

    final sut = Appdata.createForTest(settingsStore: store);
    await sut.doInit();

    expect(sut.settings['dnsOverrides'], isA<Map>());
    final map = sut.settings['dnsOverrides'] as Map;
    expect(map.entries, isNotEmpty);
    expect(map['api'], 'api.copy2000.online');
  });

  test('invalid map setting shape falls back to defaults instead of crashing', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'appdata-m25-2-map-fallback-',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);

    final store = UnifiedComicsStore.atCanonicalPath(tempDir.path);
    await store.init();
    addTearDown(store.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.upsertAppSetting(
      AppSettingRecord(
        key: 'dnsOverrides',
        valueJson: jsonEncode('api.copy2000.online'),
        valueType: 'string',
        syncPolicy: 'syncable',
        updatedAtMs: now,
      ),
    );

    App.dataPath = tempDir.path;
    final sut = Appdata.createForTest(settingsStore: store);
    await sut.doInit();

    expect(sut.settings['dnsOverrides'], isA<Map>());
    final map = sut.settings['dnsOverrides'] as Map;
    expect(map.entries, isEmpty);
  });
}
