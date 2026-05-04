import 'dart:async';

import 'package:venera/foundation/diagnostics/diagnostics.dart';

const _importLifecycleZoneKey = #veneraImportLifecycleTrace;

class ImportLifecycleTrace {
  ImportLifecycleTrace._({
    required this.id,
    required this.operation,
    required this.baseData,
  }) : _watch = Stopwatch()..start();

  final String id;
  final String operation;
  final Map<String, Object?> baseData;
  final Stopwatch _watch;

  static ImportLifecycleTrace? get current {
    final value = Zone.current[_importLifecycleZoneKey];
    return value is ImportLifecycleTrace ? value : null;
  }

  static ImportLifecycleTrace start({
    required String operation,
    String? sourceName,
    String? sourcePath,
    String? sourceType,
    Map<String, Object?> data = const {},
  }) {
    final trace = ImportLifecycleTrace._(
      id: 'import-${DateTime.now().microsecondsSinceEpoch}',
      operation: operation,
      baseData: <String, Object?>{
        'operation': operation,
        if (sourceName != null) 'sourceName': sourceName,
        if (sourcePath != null) 'sourcePath': sourcePath,
        if (sourceType != null) 'sourceType': sourceType,
        ...data,
      },
    );
    trace.info('import.lifecycle.started');
    return trace;
  }

  Future<T> run<T>(Future<T> Function() action) {
    return runZoned(action, zoneValues: {_importLifecycleZoneKey: this});
  }

  void phase(String phase, {Map<String, Object?> data = const {}}) {
    AppDiagnostics.trace(
      'import.lifecycle',
      'import.lifecycle.phase',
      data: _eventData(<String, Object?>{'phase': phase, ...data}),
    );
  }

  void info(String message, {Map<String, Object?> data = const {}}) {
    AppDiagnostics.info('import.lifecycle', message, data: _eventData(data));
  }

  void completed({Map<String, Object?> data = const {}}) {
    _watch.stop();
    AppDiagnostics.info(
      'import.lifecycle',
      'import.lifecycle.completed',
      data: _eventData(data),
    );
  }

  void failed(
    Object error, {
    StackTrace? stackTrace,
    String? phase,
    Map<String, Object?> data = const {},
  }) {
    _watch.stop();
    AppDiagnostics.error(
      'import.lifecycle',
      error,
      stackTrace: stackTrace,
      message: 'import.lifecycle.failed',
      data: _eventData(<String, Object?>{
        if (phase != null) 'phase': phase,
        'errorType': error.runtimeType.toString(),
        ...data,
      }),
    );
  }

  Map<String, Object?> _eventData(Map<String, Object?> data) {
    return <String, Object?>{
      'importId': id,
      ...baseData,
      'elapsedMs': _watch.elapsedMilliseconds,
      ...data,
    };
  }
}
