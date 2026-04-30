import 'cache_keys.dart';
import 'gateway.dart';
import 'models.dart';
import 'ports.dart';
import 'session.dart';

class ReaderNextRuntime {
  ReaderNextRuntime({
    required RemoteAdapterGateway gateway,
    required ReaderSessionStore sessionStore,
    ImageCacheStore imageCacheStore = const NoopImageCacheStore(),
  }) : _gateway = gateway,
       _sessionStore = sessionStore,
       _imageCacheStore = imageCacheStore;

  final RemoteAdapterGateway _gateway;
  final ReaderSessionStore _sessionStore;
  final ImageCacheStore _imageCacheStore;

  Future<List<SearchResultItem>> search({
    required String sourceKey,
    required String keyword,
    int page = 1,
  }) {
    if (sourceKey.isEmpty || keyword.trim().isEmpty) {
      throw ReaderRuntimeException('SEARCH_INVALID', 'sourceKey and keyword are required');
    }
    return _gateway.search(
      sourceKey: sourceKey,
      query: SearchQuery(keyword: keyword.trim(), page: page),
    );
  }

  Future<ComicDetailResult> loadComicDetail({
    required ComicIdentity identity,
  }) {
    return _gateway.loadComicDetail(identity: identity);
  }

  Future<List<ReaderImageRefWithCacheKey>> loadReaderPage({
    required ComicIdentity identity,
    required String chapterRefId,
    required int page,
  }) async {
    final images = await _gateway.loadReaderPageImages(
      identity: identity,
      chapterRefId: chapterRefId,
      page: page,
    );

    return images
        .map(
          (image) => ReaderImageRefWithCacheKey(
            image: image,
            cacheKey: buildReaderImageCacheKey(
              sourceRef: identity.sourceRef,
              canonicalComicId: identity.canonicalComicId,
              upstreamComicRefId: identity.sourceRef.upstreamComicRefId,
              chapterRefId: chapterRefId,
              imageKey: image.imageKey,
            ),
          ),
        )
        .toList();
  }

  Future<void> saveResumeSession({
    required ComicIdentity identity,
    required String chapterRefId,
    required int page,
  }) {
    final session = ReaderResumeSession(
      canonicalComicId: identity.canonicalComicId,
      sourceRef: identity.sourceRef,
      chapterRefId: chapterRefId,
      page: page,
    );
    return _sessionStore.save(session);
  }

  Future<ReaderResumeSession?> loadResumeSession({
    required String canonicalComicId,
  }) {
    if (!canonicalComicId.contains(':')) {
      throw ReaderRuntimeException(
        'CANONICAL_ID_INVALID',
        'Resume lookup requires namespaced canonicalComicId',
      );
    }
    return _sessionStore.load(canonicalComicId: canonicalComicId);
  }

  Future<ReaderImageBytesResult> loadImageBytes({
    required ReaderImageRefWithCacheKey imageWithCacheKey,
    required Future<List<int>> Function(ReaderImageRef image) fetchRemoteBytes,
  }) async {
    final cacheHit = await _imageCacheStore.read(
      cacheKey: imageWithCacheKey.cacheKey,
    );
    if (cacheHit != null) {
      return ReaderImageBytesResult(
        bytes: cacheHit,
        fromCache: true,
        image: imageWithCacheKey.image,
        cacheKey: imageWithCacheKey.cacheKey,
      );
    }

    final remoteBytes = await fetchRemoteBytes(imageWithCacheKey.image);
    await _imageCacheStore.write(
      cacheKey: imageWithCacheKey.cacheKey,
      bytes: remoteBytes,
    );
    return ReaderImageBytesResult(
      bytes: List<int>.from(remoteBytes),
      fromCache: false,
      image: imageWithCacheKey.image,
      cacheKey: imageWithCacheKey.cacheKey,
    );
  }
}

class ReaderImageRefWithCacheKey {
  const ReaderImageRefWithCacheKey({
    required this.image,
    required this.cacheKey,
  });

  final ReaderImageRef image;
  final String cacheKey;
}

class ReaderImageBytesResult {
  const ReaderImageBytesResult({
    required this.bytes,
    required this.fromCache,
    required this.image,
    required this.cacheKey,
  });

  final List<int> bytes;
  final bool fromCache;
  final ReaderImageRef image;
  final String cacheKey;
}
