import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/local/local_library_file_probe.dart';

void main() {
  final probe = const LocalLibraryFileProbe();

  test('returns missingDirectory when path is absent', () async {
    final root = await Directory.systemTemp.createTemp('probe-missing-');
    addTearDown(() => root.delete(recursive: true));

    final result = probe.probe(
      canonicalRootPath: root.path,
      comicDirectoryName: 'comic-a',
    );

    expect(result.status, LocalLibraryFileStatus.missingDirectory);
  });

  test('returns notDirectory when target is file', () async {
    final root = await Directory.systemTemp.createTemp('probe-file-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/comic-a')..writeAsStringSync('x');

    final result = probe.probe(
      canonicalRootPath: root.path,
      comicDirectoryName: file.uri.pathSegments.last,
    );

    expect(result.status, LocalLibraryFileStatus.notDirectory);
  });

  test('returns available for directory with root image', () async {
    final root = await Directory.systemTemp.createTemp('probe-available-');
    addTearDown(() => root.delete(recursive: true));
    final comic = Directory('${root.path}/comic-a')..createSync();
    File('${comic.path}/1.jpg').writeAsStringSync('x');

    final result = probe.probe(
      canonicalRootPath: root.path,
      comicDirectoryName: 'comic-a',
    );

    expect(result.status, LocalLibraryFileStatus.available);
  });

  test('returns noReadablePages for chapter-only dirs without pages', () async {
    final root = await Directory.systemTemp.createTemp('probe-empty-ch-');
    addTearDown(() => root.delete(recursive: true));
    final comic = Directory('${root.path}/comic-a')..createSync();
    Directory('${comic.path}/ch-1').createSync();

    final result = probe.probe(
      canonicalRootPath: root.path,
      comicDirectoryName: 'comic-a',
    );

    expect(result.status, LocalLibraryFileStatus.noReadablePages);
  });

  test('rejects absolute comic directory as unsafePath', () async {
    final root = await Directory.systemTemp.createTemp('probe-unsafe-');
    addTearDown(() => root.delete(recursive: true));

    final result = probe.probe(
      canonicalRootPath: root.path,
      comicDirectoryName: '/tmp/escape',
    );

    expect(result.status, LocalLibraryFileStatus.unsafePath);
  });
}
