import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/local_library_browse_store_port.dart';

class LocalLibraryRepository {
  const LocalLibraryRepository({required this.store});

  final LocalLibraryBrowseStorePort store;

  Future<List<LocalLibraryBrowseRecord>> loadBrowseRecords() {
    return store.loadLocalLibraryBrowseRecords();
  }

  Future<LocalLibraryItemRecord?> loadPrimaryLocalLibraryItem(String comicId) {
    return store.loadPrimaryLocalLibraryItem(comicId);
  }
}
