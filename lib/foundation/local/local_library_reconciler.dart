import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local/local_library_file_probe.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';

class LocalLibraryReconcileItem {
  const LocalLibraryReconcileItem({
    required this.comicId,
    required this.comicDirectoryName,
  });

  final String comicId;
  final String comicDirectoryName;
}

class LocalLibraryBrowseReconcileResult {
  const LocalLibraryBrowseReconcileResult({
    required this.visibleComicIds,
    required this.cleanupCandidateLocalLibraryItemIds,
  });

  final Set<String> visibleComicIds;
  final Set<String> cleanupCandidateLocalLibraryItemIds;
}

class LocalLibraryReconciler {
  const LocalLibraryReconciler({
    this.fileProbe = const LocalLibraryFileProbe(),
  });

  final LocalLibraryFileProbe fileProbe;

  Future<LocalLibraryBrowseReconcileResult> reconcileBrowseVisibility({
    required List<LocalLibraryReconcileItem> items,
    required Future<LocalLibraryPrimaryItem?> Function(String comicId)
    loadPrimaryItem,
  }) async {
    final visibleComicIds = <String>{};
    final cleanupCandidates = <String>{};

    for (final item in items) {
      final primaryItem = await loadPrimaryItem(item.comicId);
      if (primaryItem == null) {
        visibleComicIds.add(item.comicId);
        continue;
      }

      final probeResult = fileProbe.probe(
        canonicalRootPath: primaryItem.localRootPath,
        comicDirectoryName: item.comicDirectoryName,
        preferredExpectedDirectory: primaryItem.localRootPath,
      );

      if (probeResult.isAvailable) {
        visibleComicIds.add(item.comicId);
        continue;
      }

      if (probeResult.isCleanupCandidate) {
        cleanupCandidates.add(primaryItem.id);
      }

      AppDiagnostics.info(
        'local.library',
        'local.library.missingFiles',
        data: <String, Object?>{
          'comicId': item.comicId,
          'status': probeResult.status.name,
          'expectedDirectory': probeResult.expectedDirectory,
          'action': 'hide',
        },
      );
    }

    return LocalLibraryBrowseReconcileResult(
      visibleComicIds: visibleComicIds,
      cleanupCandidateLocalLibraryItemIds: cleanupCandidates,
    );
  }

  Future<int> cleanupMissingUserImportedItems({
    required List<LocalLibraryReconcileItem> items,
    required Future<LocalLibraryPrimaryItem?> Function(String comicId)
    loadPrimaryItem,
    required Future<void> Function(String localLibraryItemId)
    deleteLocalLibraryItem,
  }) async {
    var removed = 0;
    for (final item in items) {
      final primaryItem = await loadPrimaryItem(item.comicId);
      if (primaryItem == null || primaryItem.storageType != 'user_imported') {
        continue;
      }
      final probeResult = fileProbe.probe(
        canonicalRootPath: primaryItem.localRootPath,
        comicDirectoryName: item.comicDirectoryName,
        preferredExpectedDirectory: primaryItem.localRootPath,
      );
      if (!probeResult.isCleanupCandidate) {
        continue;
      }
      if (probeResult.status == LocalLibraryFileStatus.unsafePath) {
        continue;
      }

      AppDiagnostics.info(
        'local.library',
        'local.library.missingFiles',
        data: <String, Object?>{
          'comicId': item.comicId,
          'status': probeResult.status.name,
          'expectedDirectory': probeResult.expectedDirectory,
          'action': 'cleanup_candidate',
        },
      );

      await deleteLocalLibraryItem(primaryItem.id);
      removed++;

      AppDiagnostics.info(
        'local.library',
        'local.library.missingFiles',
        data: <String, Object?>{
          'comicId': item.comicId,
          'status': probeResult.status.name,
          'expectedDirectory': probeResult.expectedDirectory,
          'action': 'removed',
        },
      );
    }
    return removed;
  }
}
