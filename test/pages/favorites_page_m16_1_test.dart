import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/bridge/favorites_route_cutover_controller.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_route_readiness_gate.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/pages/favorites/favorites_page.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  FavoriteItem buildFavorite({
    String id = '646922',
    String sourceKey = 'nhentai',
  }) {
    return FavoriteItem(
      id: id,
      name: 'Fav',
      coverPath: 'cover',
      author: 'a',
      type: ComicType.fromKey(sourceKey),
      tags: const <String>[],
    );
  }

  test('favorites page preflight helper uses row context only', () {
    const controller = FavoritesRouteCutoverController();
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: false,
      allowHistory: false,
      allowFavorites: false,
      allowDownloads: false,
    );

    final comic = buildFavorite();
    final result = evaluateFavoritesPreflightForRowContext(
      controller: controller,
      comic: comic,
      folderName: 'Folder-A',
      readinessArtifact: artifact,
      isRowStale: false,
    );

    expect(result.diagnostic.recordKind, 'favorites');
    expect(result.diagnostic.folderName, 'Folder-A');
    expect(result.diagnostic.sourceKey, comic.sourceKey);
    expect(result.decision, FavoritesRouteDecision.blocked);
  });

  test('favorites page preflight helper keeps duplicate folder rows independent', () {
    const controller = FavoritesRouteCutoverController();
    const artifact = ReadinessArtifact(
      readinessArtifactSchemaVersion: m14ReadinessArtifactSchemaVersion,
      sourceSchemaVersion: 1,
      postApplyVerified: true,
      allowHistory: false,
      allowFavorites: true,
      allowDownloads: false,
    );

    final a = evaluateFavoritesPreflightForRowContext(
      controller: controller,
      comic: buildFavorite(id: '646922'),
      folderName: 'Folder-A',
      readinessArtifact: artifact,
    );
    final b = evaluateFavoritesPreflightForRowContext(
      controller: controller,
      comic: buildFavorite(id: '646922'),
      folderName: 'Folder-B',
      readinessArtifact: artifact,
    );

    expect(a.candidate?.candidateId, isNotNull);
    expect(b.candidate?.candidateId, isNotNull);
    expect(a.candidate!.candidateId, isNot(equals(b.candidate!.candidateId)));
  });

  test('favorites injected executor overrides default executor', () async {
    var defaultFactoryCalls = 0;
    var injectedExecutorCalls = 0;
    final request = ReaderNextOpenRequest.remote(
      canonicalComicId: CanonicalComicId.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
      ),
      sourceRef: SourceRef.remote(
        sourceKey: 'nhentai',
        upstreamComicRefId: '646922',
      ),
      initialPage: 1,
    );
    Future<void> injected(ReaderNextOpenRequest req) async {
      injectedExecutorCalls += 1;
      expect(identical(req, request), isTrue);
    }

    final resolved = resolveFavoritesReaderNextExecutor(
      injectedExecutor: injected,
      injectedFactory: () {
        defaultFactoryCalls += 1;
        return (_) async {};
      },
    );
    await resolved!(request);
    expect(injectedExecutorCalls, 1);
    expect(defaultFactoryCalls, 0);
  });
}
