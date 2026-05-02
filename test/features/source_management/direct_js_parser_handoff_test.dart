import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/direct_js_parser_handoff.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';

void main() {
  group('Direct JS parser handoff (D3c5 tests-first)', () {
    late Directory tempDir;
    late File committedFile;
    late List<String> callOrder;
    late ComicSource registeredSource;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('d3c5_parser_handoff_');
      committedFile = File('${tempDir.path}/committed.js');
      await committedFile.writeAsString('class Demo extends ComicSource {}');
      callOrder = <String>[];
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'direct js parser handoff parses committed staged file through existing parser path',
      () async {
        final handoff = DirectJsParserHandoff(
          createAndParse: (sourceJs, fileName) async {
            callOrder.add('parse');
            return _buildSource(key: 'demo_source');
          },
          registerSource: (source) {
            callOrder.add('register');
            registeredSource = source;
          },
        );

        final result = await handoff.handoff(
          committedFile: committedFile,
          sourceScript: 'class Demo extends ComicSource {}',
          fileName: 'demo_source.js',
          validatedSourceKey: 'demo_source',
        );

        expect(result, isA<SourceCommandSuccess>());
        expect(callOrder, <String>['parse', 'register']);
        expect(registeredSource.key, 'demo_source');
        expect(await committedFile.exists(), isTrue);
      },
    );

    test('direct js parser handoff rolls back committed file when parser fails', () async {
      var registerCalled = false;
      final handoff = DirectJsParserHandoff(
        createAndParse: (_, __) async {
          callOrder.add('parse');
          throw StateError('parse fail');
        },
        registerSource: (_) {
          registerCalled = true;
        },
      );

      final result = await handoff.handoff(
        committedFile: committedFile,
        sourceScript: 'class Demo extends ComicSource {}',
        fileName: 'demo_source.js',
        validatedSourceKey: 'demo_source',
      );

      expect(result, isA<SourceCommandFailed>());
      expect((result as SourceCommandFailed).code, sourceInstallBlockedCode);
      expect(registerCalled, isFalse);
      expect(await committedFile.exists(), isFalse);
    });

    test(
      'direct js parser handoff rolls back committed file when parsed source key mismatches validated key',
      () async {
        var registerCalled = false;
        final handoff = DirectJsParserHandoff(
          createAndParse: (_, __) async {
            callOrder.add('parse');
            return _buildSource(key: 'parsed_key');
          },
          registerSource: (_) {
            registerCalled = true;
          },
        );

        final result = await handoff.handoff(
          committedFile: committedFile,
          sourceScript: 'class Demo extends ComicSource {}',
          fileName: 'demo_source.js',
          validatedSourceKey: 'validated_key',
        );

        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceKeyMismatchCode);
        expect(registerCalled, isFalse);
        expect(await committedFile.exists(), isFalse);
      },
    );

    test(
      'direct js parser handoff does not call ComicSourceManager before parser success',
      () async {
        var parseStarted = false;
        final handoff = DirectJsParserHandoff(
          createAndParse: (_, __) async {
            parseStarted = true;
            callOrder.add('parse');
            return _buildSource(key: 'demo_source');
          },
          registerSource: (_) {
            expect(parseStarted, isTrue);
            callOrder.add('register');
          },
        );

        final result = await handoff.handoff(
          committedFile: committedFile,
          sourceScript: 'class Demo extends ComicSource {}',
          fileName: 'demo_source.js',
          validatedSourceKey: 'demo_source',
        );

        expect(result, isA<SourceCommandSuccess>());
        expect(callOrder, <String>['parse', 'register']);
      },
    );
  });
}

ComicSource _buildSource({required String key}) {
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
    '/tmp/$key.js',
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
  );
}
