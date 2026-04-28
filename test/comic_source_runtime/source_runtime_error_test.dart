import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/runtime.dart';

void main() {
  test('runtime_error_diagnostic_json_excludes_cause', () {
    final error = SourceRuntimeError(
      code: SourceRuntimeCodes.legacyUnknown,
      message: 'boom',
      sourceKey: 'copymanga',
      requestId: 'req-1',
      stage: SourceRuntimeStage.legacy,
      cause: Exception('secret-cause'),
    );

    final json = error.toDiagnosticJson();

    expect(json.containsKey('cause'), isFalse);
  });

  test('runtime_error_diagnostic_json_omits_account_profile_id', () {
    final error = SourceRuntimeError(
      code: SourceRuntimeCodes.legacyUnknown,
      message: 'boom',
      sourceKey: 'copymanga',
      requestId: 'req-1',
      accountProfileId: 'account-1',
      stage: SourceRuntimeStage.legacy,
    );

    final json = error.toDiagnosticJson();

    expect(json.containsKey('accountProfileId'), isFalse);
  });

  test('runtime_error_to_string_excludes_cause_and_account_profile_id', () {
    final error = SourceRuntimeError(
      code: SourceRuntimeCodes.legacyUnknown,
      message: 'boom',
      sourceKey: 'copymanga',
      requestId: 'req-1',
      accountProfileId: 'account-1',
      stage: SourceRuntimeStage.legacy,
      cause: Exception('secret-cause'),
    );

    final text = error.toString();

    expect(text.contains('secret-cause'), isFalse);
    expect(text.contains('account-1'), isFalse);
  });
}
