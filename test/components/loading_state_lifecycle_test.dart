import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/res.dart';

class _SlowLoadedWidget extends StatefulWidget {
  const _SlowLoadedWidget({required this.release});

  final Completer<void> release;

  @override
  State<_SlowLoadedWidget> createState() => _SlowLoadedWidgetState();
}

class _SlowLoadedWidgetState
    extends LoadingState<_SlowLoadedWidget, String> {
  @override
  Future<Res<String>> loadData() async => const Res('loaded');

  @override
  Future<void> onDataLoaded() => widget.release.future;

  @override
  Widget buildContent(BuildContext context, String data) => Text(data);
}

void main() {
  testWidgets('does not call setState after dispose while onDataLoaded awaits', (
    tester,
  ) async {
    final release = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(home: _SlowLoadedWidget(release: release)),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    release.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
