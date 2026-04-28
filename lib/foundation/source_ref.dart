enum SourceRefType {
  local,
  remote,
}

class SourceRef {
  final String id;
  final SourceRefType type;
  final String sourceKey;
  final String refId;
  final String? routeKey;
  final Map<String, Object?> params;

  const SourceRef({
    required this.id,
    required this.type,
    required this.sourceKey,
    required this.refId,
    this.routeKey,
    this.params = const {},
  });

  static String _chapterToken(String? chapterId) => chapterId ?? '_';

  factory SourceRef.fromLegacyLocal({
    required String localType,
    required String localComicId,
    String? chapterId,
  }) {
    return SourceRef(
      id: 'local:$localType:$localComicId:${_chapterToken(chapterId)}',
      type: SourceRefType.local,
      sourceKey: 'local',
      refId: localComicId,
      params: {
        'localType': localType,
        'localComicId': localComicId,
        'chapterId': chapterId,
      },
    );
  }

  factory SourceRef.fromLegacyRemote({
    required String sourceKey,
    required String comicId,
    String? chapterId,
    String? routeKey,
  }) {
    return SourceRef(
      id: 'remote:$sourceKey:$comicId:${_chapterToken(chapterId)}',
      type: SourceRefType.remote,
      sourceKey: sourceKey,
      refId: comicId,
      routeKey: routeKey,
      params: {
        'comicId': comicId,
        'chapterId': chapterId,
      },
    );
  }

  factory SourceRef.fromLegacy({
    required String comicId,
    required String sourceKey,
    String? chapterId,
  }) {
    if (sourceKey == 'local') {
      return SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: comicId,
        chapterId: chapterId,
      );
    }
    return SourceRef.fromLegacyRemote(
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
    );
  }
}

class ReadingResumeTarget {
  final String seriesId;
  final String chapterEntryId;
  final String sourceRefId;
  final SourceRefType sourceRefType;
  final String sourceKey;
  final int pageIndex;
  final DateTime updatedAt;

  const ReadingResumeTarget({
    required this.seriesId,
    required this.chapterEntryId,
    required this.sourceRefId,
    required this.sourceRefType,
    required this.sourceKey,
    required this.pageIndex,
    required this.updatedAt,
  });
}
