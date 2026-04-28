import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/adaptive/app_window_class.dart';

void main() {
  test('classifyAppWidth_returns_compact_below_600', () {
    expect(classifyAppWidth(0), AppWindowClass.compact);
    expect(classifyAppWidth(320), AppWindowClass.compact);
    expect(classifyAppWidth(599.99), AppWindowClass.compact);
  });

  test('classifyAppWidth_returns_medium_from_600_inclusive_to_below_840', () {
    expect(classifyAppWidth(600), AppWindowClass.medium);
    expect(classifyAppWidth(700), AppWindowClass.medium);
    expect(classifyAppWidth(839.99), AppWindowClass.medium);
  });

  test('classifyAppWidth_returns_wide_from_840_inclusive', () {
    expect(classifyAppWidth(840), AppWindowClass.wide);
    expect(classifyAppWidth(1024), AppWindowClass.wide);
    expect(classifyAppWidth(1440), AppWindowClass.wide);
  });

  test('classifyAppWidth_boundary_transitions_are_exact', () {
    expect(classifyAppWidth(599.9999), AppWindowClass.compact);
    expect(classifyAppWidth(600), AppWindowClass.medium);
    expect(classifyAppWidth(839.9999), AppWindowClass.medium);
    expect(classifyAppWidth(840), AppWindowClass.wide);
  });
}
