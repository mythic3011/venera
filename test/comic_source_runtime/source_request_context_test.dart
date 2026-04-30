import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/runtime.dart';

void main() {
  test('source_request_context_preserves_snapshot_fields', () {
    final createdAt = DateTime.utc(2026, 4, 28, 14, 30, 0);
    final context = SourceRequestContext(
      sourceKey: 'copymanga',
      requestId: 'req-123',
      createdAt: createdAt,
      accountProfileId: 'profile-1',
      accountRevision: 4,
      headerProfile: 'default',
    );

    expect(context.sourceKey, 'copymanga');
    expect(context.requestId, 'req-123');
    expect(context.createdAt, createdAt);
    expect(context.accountProfileId, 'profile-1');
    expect(context.accountRevision, 4);
    expect(context.headerProfile, 'default');
  });

  test(
    'source_request_context_does_not_read_active_account_after_creation',
    () {
      var accountProfileId = 'profile-a';
      final context = SourceRequestContext(
        sourceKey: 'copymanga',
        requestId: 'req-456',
        createdAt: DateTime.utc(2026, 4, 28, 14, 45, 0),
        accountProfileId: accountProfileId,
        accountRevision: 1,
        headerProfile: 'stable',
      );

      accountProfileId = 'profile-b';

      expect(accountProfileId, 'profile-b');
      expect(context.accountProfileId, 'profile-a');
    },
  );
}
