import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';
import 'package:venera/features/sources/comic_source/source_management_controller.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'package:venera/utils/translations.dart';

class _FakeSourceManagementController extends SourceManagementController {
  _FakeSourceManagementController({
    List<SourceRepositoryView> repositories = const <SourceRepositoryView>[],
    List<SourcePackageView> packages = const <SourcePackageView>[],
    this.packagesAfterRefresh = const <SourcePackageView>[],
  }) : repositories = List<SourceRepositoryView>.of(repositories),
       packages = List<SourcePackageView>.of(packages);

  final List<SourceRepositoryView> repositories;
  List<SourcePackageView> packages;
  final List<SourcePackageView> packagesAfterRefresh;
  int addRepositoryCalls = 0;
  int refreshRepositoryCalls = 0;
  int refreshRepositoriesCalls = 0;
  int addSourceFromUrlCalls = 0;

  @override
  Future<List<SourceRepositoryView>> listRepositories() async => repositories;

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
  Future<void> addSourceFromUrl(String url) async {
    addSourceFromUrlCalls++;
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
    Future<SourceCommandResult> Function(String url)? validateDirectSourceUrl,
  }) async {
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
    expect(find.text('Install pending'), findsNothing);
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
      expect(find.text('1.0.0'), findsOneWidget);
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
        return const SourceCommandSuccess(
          metadata: DirectJsValidationMetadata(sourceKey: 'demo-source'),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pump();

    expect(validateCalls, 1);
    expect(find.text('Validation Result'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('direct url validation success shows disabled install state', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        return const SourceCommandSuccess(
          metadata: DirectJsValidationMetadata(
            sourceKey: 'demo-source',
            name: 'Demo Source',
            version: '1.0.0',
          ),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pump();

    expect(find.text('Validation Result'), findsOneWidget);
    expect(find.textContaining('Install/write path is disabled in D2.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('direct url validation does not mutate installed sources', (
    tester,
  ) async {
    final controller = _FakeSourceManagementController();
    await pumpPage(
      tester,
      controller,
      validateDirectSourceUrl: (url) async {
        return const SourceCommandSuccess(
          metadata: DirectJsValidationMetadata(sourceKey: 'demo-source'),
        );
      },
    );

    await tester.enterText(find.byType(TextField).first, 'https://example.com/source.js');
    await tester.tap(find.text('Validate Direct URL'));
    await tester.pump();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(controller.addSourceFromUrlCalls, 0);
  });
}
