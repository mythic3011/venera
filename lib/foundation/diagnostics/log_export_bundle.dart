import 'dart:convert';

import 'package:venera/foundation/app/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/utils/io.dart';

Future<List<File>> _listStructuredArchiveFiles() async {
  if (!App.isInitialized) {
    return const [];
  }
  final logsDir = Directory(FilePath.join(App.dataPath, 'logs'));
  if (!await logsDir.exists()) {
    return const [];
  }
  final baseName = 'diagnostics.ndjson';
  final entities = await logsDir.list().toList();
  final files = entities
      .whereType<File>()
      .where((file) {
        final name = file.uri.pathSegments.last;
        return name == baseName || name.startsWith('$baseName.');
      })
      .toList(growable: false);
  files.sort((a, b) {
    final aName = a.uri.pathSegments.last;
    final bName = b.uri.pathSegments.last;
    if (aName == baseName) return -1;
    if (bName == baseName) return 1;
    return bName.compareTo(aName);
  });
  return files;
}

Future<String> _readStructuredFileForExport(File file) async {
  if (file.path.endsWith('.gz')) {
    final bytes = await file.readAsBytes();
    return utf8.decode(gzip.decode(bytes), allowMalformed: true);
  }
  return file.readAsString();
}

Future<String> buildDiagnosticsExportText() async {
  final buffer = StringBuffer();
  final structuredFiles = await _listStructuredArchiveFiles();
  final archiveFiles = structuredFiles
      .where((file) => file.uri.pathSegments.last != 'diagnostics.ndjson')
      .toList(growable: false);

  final manifest = <String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'runtimeLevel': AppDiagnostics.runtimeLevel.name,
    'persistedLevel': AppDiagnostics.persistedLevel.name,
    'includedArchives': archiveFiles.length,
    'structuredFiles': structuredFiles
        .map((file) => file.uri.pathSegments.last)
        .toList(growable: false),
  };

  buffer.writeln("=== Diagnostics Export Manifest (JSON) ===");
  buffer.writeln(jsonEncode(manifest));
  buffer.writeln();

  buffer.writeln("=== Structured Diagnostics (NDJSON) ===");
  if (structuredFiles.isEmpty) {
    final structuredNdjson = DevDiagnosticsApi.exportNdjson();
    if (structuredNdjson.trim().isEmpty) {
      buffer.writeln("(no structured diagnostics events)");
    } else {
      buffer.writeln(structuredNdjson);
    }
  } else {
    for (final file in structuredFiles) {
      final name = file.uri.pathSegments.last;
      final content = await _readStructuredFileForExport(file);
      buffer.writeln('--- $name ---');
      if (content.trim().isEmpty) {
        buffer.writeln('(empty)');
      } else {
        buffer.writeln(content);
      }
      if (!content.endsWith('\n')) {
        buffer.writeln();
      }
    }
  }
  buffer.writeln();

  buffer.write(await Log.buildExportText());
  return buffer.toString();
}

Future<File?> exportDiagnosticsToFile({String? outputPath}) async {
  if (!App.isInitialized) {
    return null;
  }
  final outPath =
      outputPath ??
      Directory(App.dataPath)
          .joinFile(
            Log.buildExportFileName(prefix: 'venera_diagnostics_export'),
          )
          .path;
  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(await buildDiagnosticsExportText());
  return file;
}
