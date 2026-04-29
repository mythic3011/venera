import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  test('source_ref_type_keys_remain_compatible', () {
    expect(sourceRefTypeKey(SourceRefType.local), 'local');
    expect(sourceRefTypeKey(SourceRefType.remote), 'remote');
    expect(sourceRefTypeFromKey('local'), SourceRefType.local);
    expect(sourceRefTypeFromKey('remote'), SourceRefType.remote);
  });

  test('source_ref_local_factory_sets_standard_params_keys', () {
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    expect(ref.type, SourceRefType.local);
    expect(ref.sourceKey, 'local');
    expect(ref.sourceIdentity.kind, localSourceKind);
    expect(ref.params['localType'], 'local');
    expect(ref.params['localComicId'], 'comic-1');
    expect(ref.params['chapterId'], 'ch-1');
  });

  test('source_ref_remote_factory_sets_standard_params_keys', () {
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    expect(ref.type, SourceRefType.remote);
    expect(ref.sourceKey, 'copymanga');
    expect(ref.sourceIdentity.key, 'copymanga');
    expect(ref.params['comicId'], 'comic-2');
    expect(ref.params['chapterId'], 'ch-2');
  });

  test('source_ref_id_is_deterministic_non_null_for_local', () {
    final a = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );
    final b = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    expect(a.id, isNotEmpty);
    expect(a.id, b.id);
    expect(a.id, 'local:local:comic-1:ch-1');
  });

  test('source_ref_id_is_deterministic_non_null_for_remote', () {
    final a = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );
    final b = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    expect(a.id, isNotEmpty);
    expect(a.id, b.id);
    expect(a.id, 'remote:copymanga:comic-2:ch-2');
  });

  test('source_ref_json_round_trip_preserves_legacy_wire_keys', () {
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    final json = ref.toJson();
    expect(json['type'], 'remote');

    final decoded = SourceRef.fromJson(Map<String, dynamic>.from(json));
    expect(decoded.type, SourceRefType.remote);
    expect(decoded.sourceKey, 'copymanga');
    expect(decoded.sourceIdentity.key, 'copymanga');
    expect(decoded.params['chapterId'], 'ch-2');
  });

  test('source_ref_invalid_type_fails_loudly', () {
    expect(
      () => SourceRef.fromJson({
        'id': 'broken',
        'type': 'bad-type',
        'sourceKey': 'copymanga',
        'refId': 'comic-1',
      }),
      throwsArgumentError,
    );
  });
}
