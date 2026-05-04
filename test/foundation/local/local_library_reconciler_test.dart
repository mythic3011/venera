import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local/local_library_reconciler.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test(
    'browse reconcile hides missing payload and keeps available comic',
    () async {
      final reconciler = const LocalLibraryReconciler();

      final result = await reconciler.reconcileBrowseVisibility(
        items: const [
          LocalLibraryReconcileItem(
            comicId: 'missing',
            comicDirectoryName: 'm',
          ),
          LocalLibraryReconcileItem(comicId: 'ok', comicDirectoryName: 'ok'),
        ],
        loadPrimaryItem: (comicId) async {
          if (comicId == 'missing') {
            return const LocalLibraryPrimaryItem(
              id: 'lli-missing',
              storageType: 'user_imported',
              localRootPath: '/definitely/missing/path',
            );
          }
          return null;
        },
      );

      expect(result.visibleComicIds, contains('ok'));
      expect(result.visibleComicIds, isNot(contains('missing')));
      expect(
        result.cleanupCandidateLocalLibraryItemIds,
        contains('lli-missing'),
      );
      final events = DevDiagnosticsApi.recent(channel: 'local.library');
      expect(
        events.any((event) => event.message == 'local.library.missingFiles'),
        isTrue,
      );
    },
  );

  test('cleanup removes only eligible user_imported missing rows', () async {
    final reconciler = const LocalLibraryReconciler();
    final removed = <String>[];

    final count = await reconciler.cleanupMissingUserImportedItems(
      items: const [
        LocalLibraryReconcileItem(
          comicId: 'delete-me',
          comicDirectoryName: 'x',
        ),
        LocalLibraryReconcileItem(
          comicId: 'keep-unsafe',
          comicDirectoryName: '/abs/path',
        ),
        LocalLibraryReconcileItem(
          comicId: 'keep-available',
          comicDirectoryName: 'k',
        ),
      ],
      loadPrimaryItem: (comicId) async {
        if (comicId == 'delete-me') {
          return const LocalLibraryPrimaryItem(
            id: 'lli-delete',
            storageType: 'user_imported',
            localRootPath: '/missing/root/path',
          );
        }
        if (comicId == 'keep-unsafe') {
          return const LocalLibraryPrimaryItem(
            id: 'lli-unsafe',
            storageType: 'user_imported',
            localRootPath: '/root',
          );
        }
        return const LocalLibraryPrimaryItem(
          id: 'lli-available',
          storageType: 'downloaded',
          localRootPath: '/root',
        );
      },
      deleteLocalLibraryItem: (id) async {
        removed.add(id);
      },
    );

    expect(count, 1);
    expect(removed, ['lli-delete']);
  });
}
