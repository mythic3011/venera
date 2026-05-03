import 'package:flutter/services.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/pages/aggregated_search_page.dart';

bool _isHandling = false;

/// Handle text share event.
/// App will navigate to [AggregatedSearchPage] with the shared text as keyword.
void handleTextShare() async {
  if (_isHandling) return;
  _isHandling = true;

  var channel = EventChannel('venera/text_share');
  await for (var event in channel.receiveBroadcastStream()) {
    final context = await _waitForMainNavigatorContext();
    if (event is String) {
      context?.to(() => AggregatedSearchPage(keyword: event));
    }
  }
}

Future<BuildContext?> _waitForMainNavigatorContext() async {
  for (var i = 0; i < 10; i++) {
    final context = App.mainNavigatorKey?.currentContext;
    if (context != null) {
      return context;
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return null;
}
