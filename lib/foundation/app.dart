import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:venera/features/comic_detail/data/comic_detail_remote_match_repository.dart';
import 'package:venera/features/comic_detail/data/comic_detail_repository.dart';
import 'package:venera/features/reader/data/reader_activity_repository.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/features/reader/data/reader_status_repository.dart';
import 'package:venera/foundation/db/adapters/unified_comic_detail_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_local_library_browse_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_reader_activity_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_reader_session_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_reader_status_store_adapter.dart';
import 'package:venera/foundation/db/adapters/unified_remote_match_store_adapter.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/comic_detail_store_port.dart';
import 'package:venera/foundation/repositories/comic_user_tags_repository.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';

import 'appdata.dart';

export "widget_utils.dart";
export "context.dart";

class _App {
  final version = "1.6.3";

  bool get isAndroid => Platform.isAndroid;

  bool get isIOS => Platform.isIOS;

  bool get isWindows => Platform.isWindows;

  bool get isLinux => Platform.isLinux;

  bool get isMacOS => Platform.isMacOS;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  // Whether the app has been initialized.
  // If current Isolate is main Isolate, this value is always true.
  bool isInitialized = false;

  Locale get locale {
    Locale deviceLocale = PlatformDispatcher.instance.locale;
    if (deviceLocale.languageCode == "zh" &&
        deviceLocale.scriptCode == "Hant") {
      deviceLocale = const Locale("zh", "TW");
    }
    if (appdata.settings['language'] != 'system') {
      return Locale(
        appdata.settings['language'].split('-')[0],
        appdata.settings['language'].split('-')[1],
      );
    }
    return deviceLocale;
  }

  late String dataPath;
  late String cachePath;
  String? externalStoragePath;

  final rootNavigatorKey = GlobalKey<NavigatorState>();

  GlobalKey<NavigatorState>? mainNavigatorKey;

  BuildContext get rootContext => rootNavigatorKey.currentContext!;

  final Appdata data = appdata;

  late AppRepositories repositories;
  late final UnifiedComicsStore _unifiedComicsStore;
  UnifiedComicsStore? _runtimeCanonicalStoreOverride;
  bool _hasUnifiedComicsStore = false;

  @Deprecated(
    'Use App.repositories instead. Direct store access is allowed only for bootstrap, migrations, imports, and legacy compatibility code.',
  )
  UnifiedComicsStore get unifiedComicsStore =>
      _runtimeCanonicalStoreOverride ?? _unifiedComicsStore;

  UnifiedComicsStore? get unifiedComicsStoreOrNull {
    if (_runtimeCanonicalStoreOverride != null) {
      return _runtimeCanonicalStoreOverride;
    }
    if (_hasUnifiedComicsStore) {
      return _unifiedComicsStore;
    }
    return null;
  }

  void rootPop() {
    rootNavigatorKey.currentState?.maybePop();
  }

  void pop() {
    if (rootNavigatorKey.currentState?.canPop() ?? false) {
      rootNavigatorKey.currentState?.pop();
    } else if (mainNavigatorKey?.currentState?.canPop() ?? false) {
      mainNavigatorKey?.currentState?.pop();
    }
  }

  Future<void> init() async {
    cachePath = (await getApplicationCacheDirectory()).path;
    dataPath = (await getApplicationSupportDirectory()).path;
    _unifiedComicsStore = UnifiedComicsStore.atCanonicalPath(dataPath);
    _hasUnifiedComicsStore = true;
    _runtimeCanonicalStoreOverride = null;
    if (isAndroid) {
      externalStoragePath = (await getExternalStorageDirectory())!.path;
    }
    isInitialized = true;
  }

  Future<void> initComponents() async {
    await initRuntimeComponents();
  }

  Future<void> initRuntimeComponents({
    Future<void> Function()? initAppData,
    UnifiedComicsStore? canonicalStore,
    Future<void> Function()? initCanonicalStore,
    Future<void> Function()? seedSourcePlatforms,
  }) async {
    final runtimeStore = canonicalStore ?? _unifiedComicsStore;
    _runtimeCanonicalStoreOverride = canonicalStore;
    await Future.wait([
      (initAppData ?? data.init)(),
      () async {
        await (initCanonicalStore ?? runtimeStore.init)();
        await (seedSourcePlatforms ?? runtimeStore.seedDefaultSourcePlatforms)();
      }(),
    ]);
    final comicDetailStore = UnifiedComicDetailStoreAdapter(
      runtimeStore,
    );
    repositories = AppRepositories(
      readerSession: ReaderSessionRepository(
        store: UnifiedReaderSessionStoreAdapter(runtimeStore),
      ),
      readerActivity: ReaderActivityRepository(
        store: UnifiedReaderActivityStoreAdapter(runtimeStore),
      ),
      readerStatus: ReaderStatusRepository(
        store: UnifiedReaderStatusStoreAdapter(runtimeStore),
      ),
      comicDetail: UnifiedCanonicalComicDetailRepository(
        store: comicDetailStore,
      ),
      comicUserTags: ComicUserTagsRepository(store: comicDetailStore),
      comicDetailStore: comicDetailStore,
      remoteMatch: RemoteMatchRepository(
        store: UnifiedRemoteMatchStoreAdapter(runtimeStore),
      ),
      localLibrary: LocalLibraryRepository(
        store: UnifiedLocalLibraryBrowseStoreAdapter(runtimeStore),
      ),
    );
  }

  Function? _forceRebuildHandler;

  void registerForceRebuild(Function handler) {
    _forceRebuildHandler = handler;
  }

  void forceRebuild() {
    _forceRebuildHandler?.call();
  }
}

class AppRepositories {
  final ReaderSessionRepository readerSession;
  final ReaderActivityRepository readerActivity;
  final ReaderStatusRepository readerStatus;
  final ComicDetailRepository comicDetail;
  final ComicUserTagsRepository comicUserTags;
  final ComicDetailStorePort comicDetailStore;
  final RemoteMatchRepository remoteMatch;
  final LocalLibraryRepository localLibrary;

  const AppRepositories({
    required this.readerSession,
    required this.readerActivity,
    required this.readerStatus,
    required this.comicDetail,
    required this.comicUserTags,
    required this.comicDetailStore,
    required this.remoteMatch,
    required this.localLibrary,
  });
}

// ignore: non_constant_identifier_names
final App = _App();
