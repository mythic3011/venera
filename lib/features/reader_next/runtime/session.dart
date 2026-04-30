import 'models.dart';

class ReaderResumeSession {
  const ReaderResumeSession({
    required this.canonicalComicId,
    required this.sourceRef,
    required this.chapterRefId,
    required this.page,
  });

  final String canonicalComicId;
  final SourceRef sourceRef;
  final String chapterRefId;
  final int page;

  void validate() {
    if (!sourceRef.isRemote) {
      throw ReaderRuntimeException(
        'SOURCE_REF_REQUIRED',
        'Resume session requires remote SourceRef for remote reader flow',
      );
    }
    if (!canonicalComicId.contains(':')) {
      throw ReaderRuntimeException(
        'CANONICAL_ID_INVALID',
        'Resume session canonicalComicId must be namespaced',
      );
    }
    if (chapterRefId.isEmpty || page < 0) {
      throw ReaderRuntimeException('SESSION_INVALID', 'Resume session is malformed');
    }
  }
}

abstract interface class ReaderSessionStore {
  Future<void> save(ReaderResumeSession session);

  Future<ReaderResumeSession?> load({required String canonicalComicId});
}

class InMemoryReaderSessionStore implements ReaderSessionStore {
  final Map<String, ReaderResumeSession> _sessions = <String, ReaderResumeSession>{};

  @override
  Future<void> save(ReaderResumeSession session) async {
    session.validate();
    _sessions[session.canonicalComicId] = session;
  }

  @override
  Future<ReaderResumeSession?> load({required String canonicalComicId}) async {
    return _sessions[canonicalComicId];
  }
}
