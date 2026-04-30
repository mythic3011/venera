import 'source_runtime_stage.dart';

class SourceRuntimeError implements Exception {
  final String code;
  final String message;
  final String sourceKey;
  final String? requestId;
  final String? accountProfileId;
  final SourceRuntimeStage stage;
  final Object? cause;

  const SourceRuntimeError({
    required this.code,
    required this.message,
    required this.sourceKey,
    required this.stage,
    this.requestId,
    this.accountProfileId,
    this.cause,
  });

  Map<String, Object?> toDiagnosticJson() => {
    'code': code,
    'message': message,
    'sourceKey': sourceKey,
    'stage': stage.name,
    if (requestId != null) 'requestId': requestId,
  };

  @override
  String toString() {
    final requestPart = requestId == null ? '' : ', requestId: $requestId';
    return 'SourceRuntimeError(code: $code, message: $message, sourceKey: $sourceKey, stage: ${stage.name}$requestPart)';
  }
}
