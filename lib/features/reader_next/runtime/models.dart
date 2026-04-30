class ReaderRuntimeException implements Exception {
  ReaderRuntimeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

enum SourceRefType { remote, local }

class SourceRef {
  const SourceRef._({
    required this.type,
    required this.sourceKey,
    required this.upstreamComicRefId,
    required this.chapterRefId,
  });

  factory SourceRef.remote({
    required String sourceKey,
    required String upstreamComicRefId,
    String? chapterRefId,
  }) {
    if (sourceKey.isEmpty) {
      throw ReaderRuntimeException(
        'SOURCE_REF_INVALID',
        'sourceKey is required for remote SourceRef',
      );
    }
    if (upstreamComicRefId.isEmpty) {
      throw ReaderRuntimeException(
        'SOURCE_REF_INVALID',
        'upstreamComicRefId is required for remote SourceRef',
      );
    }
    if (_looksCanonical(upstreamComicRefId)) {
      throw ReaderRuntimeException(
        'SOURCE_REF_INVALID',
        'upstreamComicRefId must not be canonical',
      );
    }
    return SourceRef._(
      type: SourceRefType.remote,
      sourceKey: sourceKey,
      upstreamComicRefId: upstreamComicRefId,
      chapterRefId: chapterRefId,
    );
  }

  factory SourceRef.local({
    required String sourceKey,
    required String comicRefId,
    String? chapterRefId,
  }) {
    if (sourceKey.isEmpty || comicRefId.isEmpty) {
      throw ReaderRuntimeException('SOURCE_REF_INVALID', 'Local SourceRef is malformed');
    }
    return SourceRef._(
      type: SourceRefType.local,
      sourceKey: sourceKey,
      upstreamComicRefId: comicRefId,
      chapterRefId: chapterRefId,
    );
  }

  final SourceRefType type;
  final String sourceKey;
  final String upstreamComicRefId;
  final String? chapterRefId;

  bool get isRemote => type == SourceRefType.remote;

  static bool _looksCanonical(String id) => id.contains(':');
}

class ComicIdentity {
  const ComicIdentity({
    required this.canonicalComicId,
    required this.sourceRef,
  });

  final String canonicalComicId;
  final SourceRef sourceRef;

  void assertRemoteOperationSafe() {
    if (!sourceRef.isRemote) {
      throw ReaderRuntimeException(
        'SOURCE_REF_REQUIRED',
        'Remote reader operation requires remote SourceRef',
      );
    }
    if (canonicalComicId.isEmpty || !canonicalComicId.contains(':')) {
      throw ReaderRuntimeException(
        'CANONICAL_ID_INVALID',
        'canonicalComicId must be namespaced and non-empty',
      );
    }
    if (sourceRef.upstreamComicRefId.contains(':')) {
      throw ReaderRuntimeException(
        'UPSTREAM_ID_INVALID',
        'upstream ID must never be canonical',
      );
    }
  }
}

class SearchQuery {
  const SearchQuery({required this.keyword, required this.page});

  final String keyword;
  final int page;
}

class SearchResultItem {
  const SearchResultItem({
    required this.upstreamComicRefId,
    required this.title,
    required this.cover,
    required this.tags,
  });

  final String upstreamComicRefId;
  final String title;
  final String cover;
  final List<String> tags;
}

class ComicDetailResult {
  const ComicDetailResult({
    required this.title,
    required this.description,
    required this.chapters,
  });

  final String title;
  final String description;
  final List<ChapterRef> chapters;
}

class ChapterRef {
  const ChapterRef({required this.chapterRefId, required this.title});

  final String chapterRefId;
  final String title;
}

class ReaderImageRef {
  const ReaderImageRef({
    required this.imageKey,
    required this.imageUrl,
  });

  final String imageKey;
  final String imageUrl;
}
