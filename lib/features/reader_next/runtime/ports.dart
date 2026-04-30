abstract interface class ImageCacheStore {
  Future<List<int>?> read({required String cacheKey});

  Future<void> write({
    required String cacheKey,
    required List<int> bytes,
  });
}

class InMemoryImageCacheStore implements ImageCacheStore {
  final Map<String, List<int>> _cache = <String, List<int>>{};

  @override
  Future<List<int>?> read({required String cacheKey}) async {
    final value = _cache[cacheKey];
    if (value == null) {
      return null;
    }
    return List<int>.from(value);
  }

  @override
  Future<void> write({
    required String cacheKey,
    required List<int> bytes,
  }) async {
    _cache[cacheKey] = List<int>.from(bytes);
  }
}

class NoopImageCacheStore implements ImageCacheStore {
  const NoopImageCacheStore();

  @override
  Future<List<int>?> read({required String cacheKey}) async => null;

  @override
  Future<void> write({
    required String cacheKey,
    required List<int> bytes,
  }) async {}
}
