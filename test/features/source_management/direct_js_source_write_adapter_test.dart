import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/direct_js_staged_source_writer.dart';

void main() {
  group('Direct JS staged source writer (D3c4 minimal staging utility)', () {
    late Directory tempDir;
    late Directory activeDir;
    late Directory stagedDir;
    late DirectJsStagedSourceWriter writer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('d3c4_staged_writer_');
      activeDir = Directory('${tempDir.path}/comic_source_active')..createSync();
      stagedDir = Directory('${tempDir.path}/comic_source_staged')..createSync();
      writer = DirectJsStagedSourceWriter(
        activeDir: activeDir,
        stagedDir: stagedDir,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'production staged writer creates staged file outside active scan path',
      () async {
        final staged = await writer.createStagedFile(
        fileName: 'demo_source.js',
        bytes: 'class Demo extends ComicSource {}'.codeUnits,
      );

        expect(staged.path.startsWith(stagedDir.path), isTrue);
        expect(staged.path.startsWith(activeDir.path), isFalse);
        expect(await staged.exists(), isTrue);
        expect(await File('${activeDir.path}/demo_source.js').exists(), isFalse);
      },
    );

    test('production staged writer deletes staged file on validation failure', () async {
      final committed = await writer.stageValidateAndCommit(
        fileName: 'bad_source.js',
        bytes: 'class Bad extends ComicSource {}'.codeUnits,
        validateStaged: (_) async => false,
      );

      expect(committed, isNull);
      expect(stagedDir.listSync(recursive: true), isEmpty);
      expect(await File('${activeDir.path}/bad_source.js').exists(), isFalse);
    });

    test('production staged writer keeps final file invisible before commit', () async {
      final staged = await writer.createStagedFile(
        fileName: 'pending_source.js',
        bytes: 'class Pending extends ComicSource {}'.codeUnits,
      );
      final activeFile = File('${activeDir.path}/pending_source.js');

      expect(await staged.exists(), isTrue);
      expect(await activeFile.exists(), isFalse);

      await writer.commitStagedFile(staged, activeFileName: 'pending_source.js');
      expect(await activeFile.exists(), isTrue);
      expect(await staged.exists(), isFalse);
    });

    test('production staged writer rejects fileName path traversal', () async {
      expect(
        () => writer.createStagedFile(
          fileName: '../escape.js',
          bytes: 'bad'.codeUnits,
        ),
        throwsA(isA<DirectJsStagedSourceWriterException>()),
      );
      expect(stagedDir.listSync(recursive: true), isEmpty);
    });

    test('production staged writer rejects commit when final target already exists', () async {
      final existing = File('${activeDir.path}/existing.js');
      await existing.writeAsString('existing-content');

      final staged = await writer.createStagedFile(
        fileName: 'existing.js',
        bytes: 'new-content'.codeUnits,
      );

      await expectLater(
        () => writer.commitStagedFile(staged, activeFileName: 'existing.js'),
        throwsA(isA<DirectJsStagedSourceWriterException>()),
      );

      expect(await existing.readAsString(), 'existing-content');
      expect(await staged.exists(), isTrue);
    });
  });
}
