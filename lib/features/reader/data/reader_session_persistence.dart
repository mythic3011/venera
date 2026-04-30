import 'package:flutter/foundation.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';

typedef ReaderSessionEventRecorder =
    void Function(
      String event, {
      required ReaderRuntimeContext context,
      String? sessionId,
      String? tabId,
      String? pageOrderId,
    });

void recordReaderSessionDiagnosticEvent(
  String event, {
  required ReaderRuntimeContext context,
  String? sessionId,
  String? tabId,
  String? pageOrderId,
}) {
  ReaderDiagnostics.recordCanonicalSessionEvent(
    event: event,
    loadMode: context.loadMode,
    sourceKey: context.sourceKey,
    comicId: context.canonicalComicId,
    chapterId: context.chapterId,
    chapterIndex: context.chapterIndex,
    page: context.page,
    sessionId: sessionId,
    tabId: tabId,
    pageOrderId: pageOrderId,
  );
}

class ReaderSessionPersistenceService {
  const ReaderSessionPersistenceService({
    required this.repository,
    this.recordEvent,
  });

  final ReaderSessionRepository repository;
  final ReaderSessionEventRecorder? recordEvent;

  Future<void> persistCurrentLocation(
    ReaderRuntimeContext context, {
    String? pageOrderId,
  }) async {
    final sessionId = ReaderSessionRepository.sessionIdForComic(
      context.canonicalComicId,
    );
    final tabId = ReaderSessionRepository.defaultTabIdForSourceRef(
      context.sourceRef,
    );
    recordEvent?.call(
      'reader.session.upsert.start',
      context: context,
      sessionId: sessionId,
      tabId: tabId,
      pageOrderId: pageOrderId,
    );
    await repository.upsertCurrentLocation(
      comicId: context.canonicalComicId,
      chapterId: context.chapterId,
      pageIndex: context.page,
      sourceRef: context.sourceRef,
      pageOrderId: pageOrderId,
    );
    recordEvent?.call(
      'reader.session.upsert.success',
      context: context,
      sessionId: sessionId,
      tabId: tabId,
      pageOrderId: pageOrderId,
    );
  }
}

@visibleForTesting
Future<void> persistReaderSessionContextForTesting({
  required ReaderSessionRepository repository,
  required ReaderRuntimeContext context,
  String? pageOrderId,
  ReaderSessionEventRecorder? recordEvent,
}) {
  return ReaderSessionPersistenceService(
    repository: repository,
    recordEvent: recordEvent,
  ).persistCurrentLocation(context, pageOrderId: pageOrderId);
}
