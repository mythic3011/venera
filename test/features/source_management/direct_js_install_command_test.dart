import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/direct_js_install_command.dart';
import 'package:venera/features/sources/comic_source/direct_js_parser_handoff.dart'
    hide sourceInstallBlockedCode, sourceKeyMismatchCode;
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';
import 'package:venera/features/sources/comic_source/direct_js_staged_source_writer.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';

void main() {
  group('Direct JS install command guards', () {
    late _FakeDirectJsSourceWriteAdapter adapter;
    late DirectJsInstallCommand command;

    setUp(() {
      adapter = _FakeDirectJsSourceWriteAdapter();
      command = DirectJsInstallCommand(adapter: adapter);
    });

    DirectJsInstallRequest buildRequest({
      bool confirmInstall = true,
      bool allowOverwrite = false,
      String validatedKey = 'demo_source',
      String parsedKey = 'demo_source',
    }) {
      return DirectJsInstallRequest(
        sourceUrl: 'https://example.com/demo_source.js',
        sourceScript: 'class Demo extends ComicSource {}',
        validatedMetadata: DirectJsValidationMetadata(sourceKey: validatedKey),
        parsedSourceKey: parsedKey,
        confirmInstall: confirmInstall,
        allowOverwrite: allowOverwrite,
      );
    }

    test(
      'direct js install command blocks when confirmInstall is false',
      () async {
        final result = await command.execute(buildRequest(confirmInstall: false));
        expect(result, isA<SourceCommandFailed>());
        expect(
          (result as SourceCommandFailed).code,
          sourceInstallBlockedCode,
        );
        expect(adapter.writeCalls, 0);
      },
    );

    test(
      'direct js install command blocks source key collision without overwrite confirmation',
      () async {
        adapter.existingKeys.add('demo_source');
        final result = await command.execute(
          buildRequest(confirmInstall: true, allowOverwrite: false),
        );
        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceInstallKeyCollisionCode);
        expect(adapter.writeCalls, 0);
      },
    );

    test(
      'direct js install command blocks source key mismatch between validation and parsed payload',
      () async {
        final result = await command.execute(
          buildRequest(validatedKey: 'source_a', parsedKey: 'source_b'),
        );
        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceKeyMismatchCode);
        expect(adapter.writeCalls, 0);
      },
    );
  });

  group('Direct JS install production adapter (D3c6)', () {
    late Directory tempDir;
    late Directory activeDir;
    late Directory stagedDir;
    late List<String> callOrder;
    late List<String> registeredKeys;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('d3c6_install_command_');
      activeDir = Directory('${tempDir.path}/comic_source')..createSync();
      stagedDir = Directory('${tempDir.path}/comic_source_staging')
        ..createSync();
      callOrder = <String>[];
      registeredKeys = <String>[];
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    DirectJsInstallRequest buildRequest({
      String validatedKey = 'demo_source',
      String parsedKey = 'demo_source',
      bool allowOverwrite = false,
    }) {
      return DirectJsInstallRequest(
        sourceUrl: 'https://example.com/demo_source.js',
        sourceScript: 'class Demo extends ComicSource {}',
        validatedMetadata: DirectJsValidationMetadata(sourceKey: validatedKey),
        parsedSourceKey: parsedKey,
        confirmInstall: true,
        allowOverwrite: allowOverwrite,
      );
    }

    ProductionDirectJsSourceWriteAdapter buildAdapter({
      Future<ComicSource> Function(String sourceJs, String committedFilePath)?
      parse,
    }) {
      return ProductionDirectJsSourceWriteAdapter(
        activeDir: activeDir,
        stagedDir: stagedDir,
        stagedWriter: DirectJsStagedSourceWriter(
          activeDir: activeDir,
          stagedDir: stagedDir,
        ),
        parserHandoff: DirectJsParserHandoff(
          createAndParse: (sourceJs, committedFilePath) async {
            callOrder.add('parse');
            return (parse ?? _defaultParse)(sourceJs, committedFilePath);
          },
          registerSource: (source) {
            callOrder.add('register');
            registeredKeys.add(source.key);
          },
        ),
      );
    }

    test(
      'direct js install writes staged file then commits after parser success',
      () async {
        final command = DirectJsInstallCommand(adapter: buildAdapter());

        final result = await command.execute(buildRequest());

        expect(result, isA<SourceCommandSuccess>());
        expect(callOrder, <String>['parse', 'register']);
        expect(await File('${activeDir.path}/demo_source.js').exists(), isTrue);
        expect(stagedDir.listSync(recursive: true), isEmpty);
        expect(registeredKeys, <String>['demo_source']);
      },
    );

    test('direct js install rolls back committed file when parser fails', () async {
      final command = DirectJsInstallCommand(
        adapter: buildAdapter(
          parse: (_, __) async => throw StateError('parse fail'),
        ),
      );

      final result = await command.execute(buildRequest());

      expect(result, isA<SourceCommandFailed>());
      expect((result as SourceCommandFailed).code, sourceInstallBlockedCode);
      expect(await File('${activeDir.path}/demo_source.js').exists(), isFalse);
      expect(registeredKeys, isEmpty);
      expect(callOrder, <String>['parse']);
    });

    test(
      'direct js install rejects key mismatch before manager registration',
      () async {
        final command = DirectJsInstallCommand(
          adapter: buildAdapter(
            parse: (_, committedFilePath) async =>
                _buildSource(key: 'parsed_key', filePath: committedFilePath),
          ),
        );

        final result = await command.execute(
          buildRequest(validatedKey: 'validated_key', parsedKey: 'validated_key'),
        );

        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceKeyMismatchCode);
        expect(await File('${activeDir.path}/validated_key.js').exists(), isFalse);
        expect(registeredKeys, isEmpty);
        expect(callOrder, <String>['parse']);
      },
    );

    test('direct js install rejects collision without overwrite', () async {
      await File('${activeDir.path}/demo_source.js').writeAsString('existing');
      final command = DirectJsInstallCommand(adapter: buildAdapter());

      final result = await command.execute(buildRequest(allowOverwrite: false));

      expect(result, isA<SourceCommandFailed>());
      expect((result as SourceCommandFailed).code, sourceInstallKeyCollisionCode);
      expect(callOrder, isEmpty);
      expect(registeredKeys, isEmpty);
    });

    test('direct js install registers source only after parser success', () async {
      var parseCompleted = false;
      final adapter = ProductionDirectJsSourceWriteAdapter(
        activeDir: activeDir,
        stagedDir: stagedDir,
        stagedWriter: DirectJsStagedSourceWriter(
          activeDir: activeDir,
          stagedDir: stagedDir,
        ),
        parserHandoff: DirectJsParserHandoff(
          createAndParse: (sourceJs, committedFilePath) async {
            callOrder.add('parse');
            parseCompleted = true;
            return _defaultParse(sourceJs, committedFilePath);
          },
          registerSource: (source) {
            expect(parseCompleted, isTrue);
            callOrder.add('register');
            registeredKeys.add(source.key);
          },
        ),
      );
      final command = DirectJsInstallCommand(adapter: adapter);

      final result = await command.execute(buildRequest());

      expect(result, isA<SourceCommandSuccess>());
      expect(callOrder, <String>['parse', 'register']);
      expect(registeredKeys, <String>['demo_source']);
    });
  });
}

class _FakeDirectJsSourceWriteAdapter implements DirectJsSourceWriteAdapter {
  final Set<String> existingKeys = <String>{};
  int writeCalls = 0;

  @override
  Future<bool> hasInstalledSourceKey(String sourceKey) async {
    return existingKeys.contains(sourceKey);
  }

  @override
  Future<SourceCommandResult> writeInstalledSource(
    DirectJsInstallRequest request,
  ) async {
    writeCalls++;
    existingKeys.add(request.parsedSourceKey);
    return SourceCommandSuccess(metadata: request.validatedMetadata);
  }
}

Future<ComicSource> _defaultParse(String _, String committedFilePath) async {
  return _buildSource(key: 'demo_source', filePath: committedFilePath);
}

ComicSource _buildSource({
  required String key,
  required String filePath,
}) {
  return ComicSource(
    'Demo Source',
    key,
    null,
    null,
    null,
    null,
    const <ExplorePageData>[],
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    filePath,
    'https://example.com/$key.js',
    '1.0.0',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    false,
    false,
    null,
    null,
    identity: sourceIdentityFromKey(key, names: const ['Demo Source']),
  );
}
