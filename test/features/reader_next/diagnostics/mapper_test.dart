import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/reader_next/diagnostics/errors.dart';
import 'package:venera/features/reader_next/diagnostics/mapper.dart';
import 'package:venera/features/reader_next/runtime/models.dart';

void main() {
  group('reader next diagnostics mapper', () {
    test('maps source boundary runtime errors to typed boundary error', () {
      final err = ReaderRuntimeException(
        'UPSTREAM_ID_INVALID',
        'Adapter must not receive canonical IDs',
      );

      final mapped = mapReaderNextRuntimeError(err);
      expect(mapped, isA<ReaderNextSourceBoundaryError>());
      expect(mapped.diagnosticCode, 'UPSTREAM_ID_INVALID');
      expect(mapped.userMessage, contains('canonical'));
    });

    test('maps source ref required to source unavailable error', () {
      final err = ReaderRuntimeException(
        'SOURCE_REF_REQUIRED',
        'Remote operation requires remote SourceRef',
      );

      final mapped = mapReaderNextRuntimeError(err);
      expect(mapped, isA<ReaderNextSourceUnavailableError>());
      expect(mapped.diagnosticCode, 'SOURCE_REF_REQUIRED');
    });

    test('maps validation errors to non-retryable validation type', () {
      final err = ReaderRuntimeException(
        'CANONICAL_ID_INVALID',
        'canonicalComicId must be namespaced and non-empty',
      );

      final mapped = mapReaderNextRuntimeError(err);
      expect(mapped, isA<ReaderNextValidationError>());
      expect(mapped.retryable, isFalse);
      expect(mapped.diagnosticCode, 'CANONICAL_ID_INVALID');
    });

    test('maps unknown throwable to typed unknown error', () {
      final mapped = mapReaderNextRuntimeError(StateError('boom'));
      expect(mapped, isA<ReaderNextUnknownError>());
      expect(mapped.diagnosticCode, 'READER_NEXT_UNKNOWN');
      expect(mapped.userMessage, contains('boom'));
    });

    test('maps local resolver unavailable and boundary codes', () {
      final unavailable = mapReaderNextRuntimeError(
        ReaderRuntimeException(
          'LOCAL_STORAGE_UNAVAILABLE',
          'Local storage unavailable',
        ),
      );
      expect(unavailable, isA<ReaderNextSourceUnavailableError>());
      expect(unavailable.diagnosticCode, 'LOCAL_STORAGE_UNAVAILABLE');

      final boundary = mapReaderNextRuntimeError(
        ReaderRuntimeException(
          'LOCAL_CHAPTER_NOT_FOUND',
          'Local chapter missing',
        ),
      );
      expect(boundary, isA<ReaderNextSourceBoundaryError>());
      expect(boundary.diagnosticCode, 'LOCAL_CHAPTER_NOT_FOUND');
    });

    test('maps empty/missing page payload runtime codes to boundary errors', () {
      final remoteEmpty = mapReaderNextRuntimeError(
        ReaderRuntimeException(
          'REMOTE_PAGES_EMPTY',
          'Remote chapter has no renderable pages',
        ),
      );
      expect(remoteEmpty, isA<ReaderNextSourceBoundaryError>());
      expect(remoteEmpty.diagnosticCode, 'REMOTE_PAGES_EMPTY');

      final localMissing = mapReaderNextRuntimeError(
        ReaderRuntimeException(
          'LOCAL_PAGE_FILE_MISSING',
          'Local reader page file does not exist',
        ),
      );
      expect(localMissing, isA<ReaderNextSourceBoundaryError>());
      expect(localMissing.diagnosticCode, 'LOCAL_PAGE_FILE_MISSING');
    });
  });
}
