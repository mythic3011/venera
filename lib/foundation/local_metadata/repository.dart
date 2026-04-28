import 'dart:convert';

import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/local_metadata/models.dart';
import 'package:venera/utils/io.dart';

class LocalMetadataRepository {
  LocalMetadataRepository(this._filePath);

  final String _filePath;

  LocalMetadataDocument _doc = LocalMetadataDocument.empty();

  LocalMetadataDocument get document => _doc;

  Future<void> init() async {
    final file = File(_filePath);
    if (!await file.exists()) {
      _doc = LocalMetadataDocument.empty();
      return;
    }
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid metadata root');
      }
      _doc = LocalMetadataDocument.fromJson(decoded);
    } catch (e, s) {
      Log.error('LocalMetadata', 'Invalid metadata sidecar, fallback to legacy: $e', s);
      _doc = LocalMetadataDocument.empty();
    }
  }

  LocalSeriesMeta? getSeries(String seriesKey) => _doc.series[seriesKey];

  Future<void> upsertSeries(LocalSeriesMeta series) async {
    final newSeries = Map<String, LocalSeriesMeta>.from(_doc.series);
    newSeries[series.seriesKey] = series;
    _doc = LocalMetadataDocument(version: LocalMetadataDocument.currentVersion, series: newSeries);
    await _persist();
  }

  Future<void> removeSeries(String seriesKey) async {
    if (!_doc.series.containsKey(seriesKey)) {
      return;
    }
    final newSeries = Map<String, LocalSeriesMeta>.from(_doc.series);
    newSeries.remove(seriesKey);
    _doc = LocalMetadataDocument(version: LocalMetadataDocument.currentVersion, series: newSeries);
    await _persist();
  }

  Future<void> _persist() async {
    final file = File(_filePath);
    await file.parent.create(recursive: true);

    final tmpPath = '$_filePath.tmp';
    final tmpFile = File(tmpPath);
    final payload = jsonEncode(_doc.toJson());

    await tmpFile.writeAsString(payload, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(_filePath);
  }
}
