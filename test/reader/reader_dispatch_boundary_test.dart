import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/reader/reader_page_loader.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

class _SpyProvider implements ReadablePageProvider {
  int calls = 0;

  @override
  Future<Res<List<String>>> loadPages(SourceRef ref) async {
    calls++;
    return const Res(['ok']);
  }
}

Future<ReaderPageLoaderResult> _dispatch({
  required bool useSourceRefResolver,
  required SourceRef ref,
  required String loadMode,
  required Future<Res<List<String>>> Function() legacyLoadPages,
  required ReaderPageLoader loader,
}) async {
  return dispatchReaderPageLoad(
    useSourceRefResolver: useSourceRefResolver,
    loadMode: loadMode,
    legacyLoadPages: legacyLoadPages,
    loader: loader,
    sourceRef: ref,
  );
}

void main() {
  test('flag_off_uses_legacy_page_loading_path', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    var legacyCalls = 0;
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      useSourceRefResolver: false,
      ref: ref,
      loadMode: 'local',
      legacyLoadPages: () async {
        legacyCalls++;
        return const Res(['legacy']);
      },
      loader: loader,
    );

    expect(legacyCalls, 1);
    expect(local.calls, 0);
    expect(remote.calls, 0);
  });

  test('flag_on_uses_resolver_page_loading_path', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    var legacyCalls = 0;
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      useSourceRefResolver: true,
      ref: ref,
      loadMode: 'local',
      legacyLoadPages: () async {
        legacyCalls++;
        return const Res(['legacy']);
      },
      loader: loader,
    );

    expect(legacyCalls, 0);
    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('flag_on_local_ref_never_calls_remote_provider', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      useSourceRefResolver: true,
      ref: ref,
      loadMode: 'local',
      legacyLoadPages: () async => const Res(['legacy']),
      loader: loader,
    );

    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('flag_on_remote_ref_never_calls_local_provider', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    await _dispatch(
      useSourceRefResolver: true,
      ref: ref,
      loadMode: 'remote',
      legacyLoadPages: () async => const Res(['legacy']),
      loader: loader,
    );

    expect(local.calls, 0);
    expect(remote.calls, 1);
  });

  test(
    'direct chapter open rewrites stale resume ref to selected chapter id',
    () {
      final resumeRef = SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'comic-2',
        chapterId: 'ch-1',
      );

      final resolved = resolveComicDetailsReadSourceRef(
        comicId: 'comic-2',
        sourceKey: 'copymanga',
        chapters: const ComicChapters({
          'ch-1': 'Episode 1',
          'ch-2': 'Episode 2',
        }),
        ep: 2,
        group: null,
        resumeSourceRef: resumeRef,
      );

      expect(resolved.type, SourceRefType.remote);
      expect(resolved.sourceKey, 'copymanga');
      expect(resolved.params['chapterId'], 'ch-2');
      expect(resolved.id, isNot(resumeRef.id));
    },
  );
}
