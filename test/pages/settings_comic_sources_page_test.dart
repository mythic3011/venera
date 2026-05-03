import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/direct_js_install_command.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart'
    as djs;
import 'package:venera/foundation/sources/identity/source_identity.dart';
import 'package:venera/features/sources/comic_source/source_management_controller.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'package:venera/utils/translations.dart';

class _FakeSourceManagementController extends SourceManagementController {
  _FakeSourceManagementController({
    List<SourceRepositoryView> repositories = const <SourceRepositoryView>[],
    List<SourcePackageView> packages = const <SourcePackageView>[],
    this.packagesAfterRefresh = const <SourcePackageView>[],
    this.supportsDirectInstall = true,
  }) : repositories = List<SourceRepositoryView>.of(repositories),
       packages = List<SourcePackageView>.of(packages);

  final List<SourceRepositoryView> repositories;
  List<SourcePackageView> packages;
  final List<SourcePackageView> packagesAfterRefresh;
  int addRepositoryCalls = 0;
  int refreshRepositoryCalls = 0;
  int refreshRepositoriesCalls = 0;
  int addSourceFromUrlCalls = 0;
  int installValidatedDirectSourceCalls = 0;
  String primaryRepositoryUrl = '';
  int setPrimaryRepositoryUrlCalls = 0;
  bool supportsDirectInstall;
  djs.SourceCommandResult installResult = const djs.SourceCommandSuccess(
    metadata: djs.DirectJsValidationMetadata(sourceKey: 'demo-source'),
  );
  String? lastInstalledUrl;
  djs.DirectJsValidationMetadata? lastInstalledMetadata;
  bool? lastConfirmInstall;
  bool? lastAllowOverwrite;

  @override
  bool get supportsDirectJsInstall => supportsDirectInstall;

  @override
  Future<List<SourceRepositoryView>> listRepositories() async => repositories;

  @override
  Future<String> loadPrimaryRepositoryUrl() async => primaryRepositoryUrl;

  @override
  Future<void> setPrimaryRepositoryUrl(String indexUrl) async {
    setPrimaryRepositoryUrlCalls++;
    primaryRepositoryUrl = indexUrl;
  }

  @override
  Future<List<SourcePackageView>> listAvailablePackages({
    String? repositoryId,
  }) async {
    return packages;
  }

  @override
  Future<SourceRepositoryView> addRepository(
    String indexUrl, {
    String? name,
    bool userAdded = true,
    String trustLevel = 'user',
    bool enabled = true,
  }) async {
    addRepositoryCalls++;
    return SourceRepositoryView(
      id: 'new',
      name: name ?? 'New Repo',
      indexUrl: indexUrl,
      enabled: enabled,
      userAdded: userAdded,
      trustLevel: trustLevel,
    );
  }

  @override
  Future<int> refreshRepository(String repositoryId) async {
    refreshRepositoryCalls++;
    return 1;
  }

  @override
  Future<void> refreshRepositories({bool enabledOnly = true}) async {
    refreshRepositoriesCalls++;
    packages = List<SourcePackageView>.of(packagesAfterRefresh);
  }

  @override
  Future<RepositoryRefreshSummary> refreshRepositoriesSummary({
    bool enabledOnly = true,
  }) async {
    refreshRepositoriesCalls++;
    packages = List<SourcePackageView>.of(packagesAfterRefresh);
    return RepositoryRefreshSummary(
      refreshedRepositoryCount: repositories.where((repo) => !enabledOnly || repo.enabled).length,
      packageCount: packages.length,
      skippedCount: 0,
    );
  }

  @override
  Future<void> addSourceFromUrl(String url) async {
    addSourceFromUrlCalls++;
  }

  @override
  Future<djs.SourceCommandResult> installValidatedDirectSource({
    required String sourceUrl,
    required djs.DirectJsValidationMetadata validatedMetadata,
    required bool confirmInstall,
    bool allowOverwrite = false,
  }) async {
    installValidatedDirectSourceCalls++;
    lastInstalledUrl = sourceUrl;
    lastInstalledMetadata = validatedMetadata;
    lastConfirmInstall = confirmInstall;
    lastAllowOverwrite = allowOverwrite;
    if (installResult case djs.SourceCommandSuccess(:final metadata)) {
      ComicSourceManager().add(
        _buildTestSource(
          key: metadata.sourceKey,
          name: metadata.name ?? 'Installed Source',
        ),
      );
    }
    return installResult;
  }
}

void main() {
  setUpAll(() {
    AppTranslation.translations = <String, Map<String, String>>{
      'en_US': <String, String>{},
      'zh_HK': <String, String>{},
    };
  });

  Future<void> pumpPage(
    WidgetTester tester,
    _FakeSourceManagementController controller, {
    Future<djs.SourceCommandResult> Function(String url)? validateDirectSourceUrl,
  }) async {
    addTearDown(() {
      for (final source in ComicSource.all()) {
        ComicSourceManager().remove(source.key);
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ComicSourcePage(
          controller: controller,
          validateDirectSourceUrl: validateDirectSourceUrl,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings comic sources page exposes repository section', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(tester, controller);
    expect(find.text('Repositories'), findsOneWidget);
  });

  testWidgets('settings comic sources page exposes installed sources section', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(tester, controller);
    expect(find.text('Installed Sources', skipOffstage: false), findsOneWidget);
  });

  testWidgets('settings comic sources page exposes available sources section', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController(
      packages: const <SourcePackageView>[
        SourcePackageView(
          sourceKey: 's1',
          repositoryId: 'repo-1',
          name: 'Source One',
          availableVersion: '1.0.0',
          lastSeenAtMs: 1,
        ),
      ],
    );
    await pumpPage(tester, controller);
    expect(find.text('Available Sources'), findsOneWidget);
    expect(
      find.text(
        'Repository packages are listed for review only. Install support is not enabled yet.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('reviewOnly/installDisabled'), findsOneWidget);
    expect(find.text('Install pending'), findsNothing);
  });

  testWidgets('source page separates direct install from repository package review', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController(
      packages: const <SourcePackageView>[
        SourcePackageView(
          sourceKey: 's1',
          repositoryId: 'repo-1',
          name: 'Source One',
          availableVersion: '1.0.0',
          lastSeenAtMs: 1,
        ),
      ],
    );
    await pumpPage(tester, controller);

    expect(find.text('Direct JS Validation / Install'), findsOneWidget);
    expect(find.text('Repositories'), findsOneWidget);
    expect(find.text('Available Sources'), findsOneWidget);
  });

  testWidgets('settings add repository action uses source management controller', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(tester, controller);

    await tester.tap(find.text('Add Repository'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'https://repo.example.com/index.json',
    );
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    expect(controller.addRepositoryCalls, 1);
  });

  testWidgets(
    'settings refresh repository action uses source management controller',
    (tester) async {
      final controller = _FakeSourceManagementController(
        repositories: const <SourceRepositoryView>[
          SourceRepositoryView(
            id: 'repo-1',
            name: 'Repo 1',
            indexUrl: 'https://repo-1.example.com/index.json',
            enabled: true,
            userAdded: false,
            trustLevel: 'official',
          ),
        ],
      );
      await pumpPage(tester, controller);

      await tester.tap(find.byKey(const ValueKey('refresh-repo-repo-1')));
      await tester.pumpAndSettle();

      expect(controller.refreshRepositoryCalls, 1);
    },
  );

  testWidgets(
    'settings top refresh action reloads available packages from repositories',
    (tester) async {
      final controller = _FakeSourceManagementController(
        repositories: const <SourceRepositoryView>[
          SourceRepositoryView(
            id: 'repo-1',
            name: 'Custom Repo',
            indexUrl: 'https://repo-1.example.com/index.json',
            enabled: true,
            userAdded: true,
            trustLevel: 'user',
          ),
        ],
        packagesAfterRefresh: const <SourcePackageView>[
          SourcePackageView(
            sourceKey: 'custom_source',
            repositoryId: 'repo-1',
            name: 'Custom Source',
            availableVersion: '1.0.0',
            lastSeenAtMs: 1,
          ),
        ],
      );
      await pumpPage(tester, controller);

      expect(find.text('No available sources'), findsOneWidget);

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(controller.refreshRepositoriesCalls, 1);
      expect(find.text('Custom Source'), findsOneWidget);
      expect(find.textContaining('Version: 1.0.0'), findsOneWidget);
      expect(find.text('Refreshed 1 repos. Packages: 1, Skipped: 0.'), findsOneWidget);
    },
  );

  testWidgets('settings direct url validation action uses validator callback', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    var validateCalls = 0;
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        validateCalls++;
        return const djs.SourceCommandSuccess(
          metadata: djs.DirectJsValidationMetadata(sourceKey: 'demo-source'),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();

    expect(validateCalls, 1);
    expect(find.text('Validation passed. Ready to install.'), findsOneWidget);
  });

  testWidgets('source page shows install action only for installable direct js package', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        return const djs.SourceCommandSuccess(
          metadata: djs.DirectJsValidationMetadata(
            sourceKey: 'demo-source',
            name: 'Demo Source',
            version: '1.0.0',
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('install-validated-direct-source')), findsOneWidget);
  });

  testWidgets('source page does not show disabled install buttons for repository packages', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController(
      packages: const <SourcePackageView>[
        SourcePackageView(
          sourceKey: 's1',
          repositoryId: 'repo-1',
          name: 'Source One',
          availableVersion: '1.0.0',
          lastSeenAtMs: 1,
        ),
      ],
    );
    await pumpPage(tester, controller);

    expect(find.textContaining('reviewOnly/installDisabled'), findsOneWidget);
    expect(find.byKey(const ValueKey('install-validated-direct-source')), findsNothing);
  });

  testWidgets('source page does not expose legacy source list popup install path', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(tester, controller);

    expect(find.text('Repo URL'), findsNothing);
    expect(find.text("The URL should point to a 'index.json' file"), findsNothing);
    expect(find.text('Add Repository'), findsOneWidget);
  });

  testWidgets('direct source validation exception shows typed failure instead of throwing', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (_) async {
        throw StateError('validator crashed');
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(
      find.text('SOURCE_VALIDATION_FAILED: Unable to validate source URL'),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('install-validated-direct-source')), findsNothing);
  });

  testWidgets('direct install success reloads visible installed source state', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController()
      ..installResult = const djs.SourceCommandSuccess(
        metadata: djs.DirectJsValidationMetadata(
          sourceKey: 'demo-source',
          name: 'Installed Source',
          version: '1.0.0',
        ),
      );
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (_) async {
        return const djs.SourceCommandSuccess(
          metadata: djs.DirectJsValidationMetadata(
            sourceKey: 'demo-source',
            name: 'Installed Source',
            version: '1.0.0',
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('install-validated-direct-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(controller.installValidatedDirectSourceCalls, 1);
    expect(find.textContaining('Installed source: demo-source'), findsOneWidget);
  });

  testWidgets('repository packages remain review only and do not show install buttons', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController(
      packages: const <SourcePackageView>[
        SourcePackageView(
          sourceKey: 'review-only-source',
          repositoryId: 'repo-1',
          name: 'Review Only Source',
          availableVersion: '2.0.0',
          lastSeenAtMs: 1,
        ),
      ],
    );
    await pumpPage(tester, controller);

    expect(
      find.text(
        'Repository packages are listed for review only. Install support is not enabled yet.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('reviewOnly/installDisabled'), findsOneWidget);
    expect(find.text('Install Source'), findsNothing);
  });

  testWidgets('source install button remains hidden when write adapter is unavailable', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController(
      supportsDirectInstall: false,
    );
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        return const djs.SourceCommandSuccess(
          metadata: djs.DirectJsValidationMetadata(
            sourceKey: 'demo-source',
            name: 'Demo Source',
            version: '1.0.0',
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('install-validated-direct-source')), findsNothing);
  });

  testWidgets('source install requires explicit confirmation', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        return const djs.SourceCommandSuccess(
          metadata: djs.DirectJsValidationMetadata(sourceKey: 'demo-source'),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('install-validated-direct-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.installValidatedDirectSourceCalls, 0);
  });

  testWidgets('source install success reloads installed source list', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        return const djs.SourceCommandSuccess(
          metadata: djs.DirectJsValidationMetadata(
            sourceKey: 'demo-source',
            name: 'Demo Source',
            version: '1.0.0',
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('install-validated-direct-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(controller.installValidatedDirectSourceCalls, 1);
    expect(find.textContaining('Installed source: demo-source'), findsOneWidget);
  });

  testWidgets('source install collision shows typed error and does not overwrite', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController()
      ..installResult = const djs.SourceCommandFailed(
        code: sourceInstallKeyCollisionCode,
        message: 'Source key collision: demo-source',
      );
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        return const djs.SourceCommandSuccess(
          metadata: djs.DirectJsValidationMetadata(
            sourceKey: 'demo-source',
            name: 'Demo Source',
            version: '1.0.0',
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('install-validated-direct-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(controller.installValidatedDirectSourceCalls, 1);
    expect(controller.lastAllowOverwrite, isFalse);
    expect(find.text('SOURCE_KEY_COLLISION: Source already installed'), findsWidgets);
  });

  test('source page loads primary repository url from canonical registry', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'source-page-primary-url-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'source_registry.db'));
    await store.init();
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.upsertSourceRepository(
        SourceRepositoryRecord(
          id: 'repo-canonical',
          name: 'Canonical Repo',
          indexUrl: 'https://repo.example.com/index.json',
          enabled: true,
          userAdded: true,
          trustLevel: 'user',
          lastRefreshStatus: 'never',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      final controller = SourceManagementController(
        repositoryStoreProvider: () => store,
      );

      final url = await loadComicSourcePrimaryRepositoryUrlForTesting(controller);

      expect(url, 'https://repo.example.com/index.json');
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('source page does not persist repository url to comicSourceListUrl appdata key', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'source-page-no-appdata-write-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'source_registry.db'));
    final oldListUrl = appdata.settings['comicSourceListUrl'] as String;
    await store.init();
    try {
      appdata.settings['comicSourceListUrl'] =
          'https://example.com/legacy-index.json';
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.upsertSourceRepository(
        SourceRepositoryRecord(
          id: 'repo-canonical',
          name: 'Canonical Repo',
          indexUrl: 'https://repo.example.com/index.json',
          enabled: true,
          userAdded: true,
          trustLevel: 'user',
          lastRefreshStatus: 'never',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      final controller = SourceManagementController(
        repositoryStoreProvider: () => store,
      );

      await persistComicSourcePrimaryRepositoryUrlForTesting(
        controller,
        'https://repo-2.example.com/index.json',
      );

      expect(
        appdata.settings['comicSourceListUrl'],
        'https://example.com/legacy-index.json',
      );
      final repositories = await controller.listRepositories();
      expect(
        repositories.any(
          (repo) => repo.indexUrl == 'https://repo-2.example.com/index.json',
        ),
        isTrue,
      );
    } finally {
      appdata.settings['comicSourceListUrl'] = oldListUrl;
      await store.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}

ComicSource _buildTestSource({
  required String key,
  required String name,
}) {
  return _StaticSettingsComicSource(
    name,
    key,
    null,
    null,
    null,
    null,
    const [],
    null,
    const <String, Map<String, dynamic>>{},
    null,
    null,
    null,
    null,
    null,
    '/tmp/$key.js',
    'https://example.com/$key.js',
    '1.0.0',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    false,
    false,
    null,
    null,
    identity: sourceIdentityFromKey(key, names: [name]),
  );
}

class _StaticSettingsComicSource extends ComicSource {
  _StaticSettingsComicSource(
    super.name,
    super.key,
    super.account,
    super.categoryData,
    super.categoryComicsData,
    super.favoriteData,
    super.explorePages,
    super.searchPageData,
    super.settings,
    super.loadComicInfo,
    super.loadComicThumbnail,
    super.loadComicPages,
    super.getImageLoadingConfig,
    super.getThumbnailLoadingConfig,
    super.filePath,
    super.url,
    super.version,
    super.commentsLoader,
    super.sendCommentFunc,
    super.chapterCommentsLoader,
    super.sendChapterCommentFunc,
    super.likeOrUnlikeComic,
    super.voteCommentFunc,
    super.likeCommentFunc,
    super.idMatcher,
    super.translations,
    super.handleClickTagEvent,
    super.onTagSuggestionSelected,
    super.linkHandler,
    super.enableTagsSuggestions,
    super.enableTagsTranslate,
    super.starRatingFunc,
    super.archiveDownloader, {
    super.identity,
  });

  @override
  Map<String, Map<String, dynamic>>? getSettingsDynamic() => settings;
}
