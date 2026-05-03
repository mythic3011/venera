import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/foundation/sources/identity/source_identity.dart';

void main() {
  test('remote source ref exposes canonical identity and adapter-safe refId', () {
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'nhentai',
      comicId: '646922',
      chapterId: 'c1',
    );
    expect(ref.canonicalId, 'remote:nhentai:646922');
    expect(ref.sourceKey, 'nhentai');
    expect(ref.refId, '646922');
    expect(() => SourceIdentityPolicy.assertAdapterSafe(ref), returnsNormally);
  });

  test(
    'assertAdapterSafe throws nonCanonicalRouteKeyLeak for canonical refId leak',
    () {
      final ref = SourceRef(
        id: 'remote:nhentai:646922:c1',
        type: SourceRefType.remote,
        sourceKey: 'nhentai',
        sourceIdentity: sourceIdentityFromKey('nhentai'),
        refId: 'remote:nhentai:646922',
        params: const {'chapterId': 'c1'},
      );
      expect(
        () => SourceIdentityPolicy.assertAdapterSafe(ref),
        throwsA(
          isA<SourceIdentityError>().having(
            (e) => e.code,
            'code',
            SourceIdentityErrorCode.nonCanonicalRouteKeyLeak,
          ),
        ),
      );
    },
  );

  test('missing source key throws missingSourceKey', () {
    final ref = SourceRef(
      id: 'remote::646922:c1',
      type: SourceRefType.remote,
      sourceKey: '',
      sourceIdentity: sourceIdentityFromKey('nhentai'),
      refId: '646922',
      params: const {'chapterId': 'c1'},
    );
    expect(
      () => SourceIdentityPolicy.assertAdapterSafe(ref),
      throwsA(
        isA<SourceIdentityError>().having(
          (e) => e.code,
          'code',
          SourceIdentityErrorCode.missingSourceKey,
        ),
      ),
    );
  });

  test('missing ref id throws missingRefId', () {
    final ref = SourceRef(
      id: 'remote:nhentai::c1',
      type: SourceRefType.remote,
      sourceKey: 'nhentai',
      sourceIdentity: sourceIdentityFromKey('nhentai'),
      refId: '',
      params: const {'chapterId': 'c1'},
    );
    expect(
      () => SourceIdentityPolicy.assertAdapterSafe(ref),
      throwsA(
        isA<SourceIdentityError>().having(
          (e) => e.code,
          'code',
          SourceIdentityErrorCode.missingRefId,
        ),
      ),
    );
  });
}
