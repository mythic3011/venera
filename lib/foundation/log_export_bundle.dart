import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/utils/io.dart';

Future<String> buildDiagnosticsExportText() async {
  final buffer = StringBuffer();
  final structuredNdjson = DevDiagnosticsApi.exportNdjson();

  buffer.writeln("=== Structured Diagnostics (NDJSON) ===");
  if (structuredNdjson.trim().isEmpty) {
    buffer.writeln("(no structured diagnostics events)");
  } else {
    buffer.writeln(structuredNdjson);
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
