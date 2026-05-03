import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current;
  final legacyFilePaths = <String>[
    'lib/foundation/app.dart',
    'lib/foundation/app_page_route.dart',
    'lib/foundation/global_state.dart',
    'lib/foundation/context.dart',
    'lib/foundation/widget_utils.dart',
    'lib/foundation/source_ref.dart',
    'lib/foundation/source_identity/constants.dart',
    'lib/foundation/source_identity/models.dart',
    'lib/foundation/source_identity/source_identity.dart',
    'lib/foundation/source_identity/source_platform_resolver.dart',
    'lib/foundation/js_engine.dart',
    'lib/foundation/js_pool.dart',
    'lib/foundation/js_compute_engine.dart',
    'lib/foundation/debug_diagnostics_service.dart',
    'lib/foundation/debug_log_exporter.dart',
    'lib/foundation/log_diagnostics.dart',
    'lib/foundation/log_export_bundle.dart',
  ];

  final forbiddenImportTokens = <String>[
    "package:venera/foundation/app.dart",
    "package:venera/foundation/app_page_route.dart",
    "package:venera/foundation/global_state.dart",
    "package:venera/foundation/context.dart",
    "package:venera/foundation/widget_utils.dart",
    "package:venera/foundation/source_ref.dart",
    "package:venera/foundation/source_identity/constants.dart",
    "package:venera/foundation/source_identity/models.dart",
    "package:venera/foundation/source_identity/source_identity.dart",
    "package:venera/foundation/source_identity/source_platform_resolver.dart",
    "package:venera/foundation/js_engine.dart",
    "package:venera/foundation/js_pool.dart",
    "package:venera/foundation/js_compute_engine.dart",
    "package:venera/foundation/debug_diagnostics_service.dart",
    "package:venera/foundation/debug_log_exporter.dart",
    "package:venera/foundation/log_diagnostics.dart",
    "package:venera/foundation/log_export_bundle.dart",
    "../foundation/app.dart",
    "../foundation/app_page_route.dart",
    "../foundation/global_state.dart",
    "../foundation/context.dart",
    "../foundation/widget_utils.dart",
    "foundation/app.dart",
    "foundation/app_page_route.dart",
    "foundation/global_state.dart",
    "foundation/context.dart",
    "foundation/widget_utils.dart",
    "import 'app.dart';",
    "import 'app_page_route.dart';",
  ];

  test('legacy foundation files are removed after layout move', () {
    for (final path in legacyFilePaths) {
      final file = File('${repoRoot.path}/$path');
      expect(
        file.existsSync(),
        isFalse,
        reason: 'Legacy file must remain removed: $path',
      );
    }
  });

  test('lib and test do not import legacy foundation paths', () {
    final dartFiles = <File>[
      ...Directory('${repoRoot.path}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      ...Directory('${repoRoot.path}/test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];

    final violations = <String>[];
    final selfPath = '${repoRoot.path}/test/foundation/foundation_layout_boundary_test.dart';
    for (final file in dartFiles) {
      if (file.path == selfPath) {
        continue;
      }
      final content = file.readAsStringSync();
      for (final token in forbiddenImportTokens) {
        if (content.contains(token)) {
          violations.add('${file.path}: $token');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Found legacy imports:\n${violations.join('\n')}',
    );
  });
}
