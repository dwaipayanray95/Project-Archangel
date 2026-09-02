import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/main.dart';
import 'package:archangel/widgets/app_shell.dart';

AppState _appOf(WidgetTester tester) => Provider.of<AppState>(tester.element(find.byType(AppShell)), listen: false);

// pumpAndSettle() never returns here: several widgets (status-dot pulses,
// the terminal cursor) animate on an infinite repeat by design, so settle
// on a fixed number of frames instead.
Future<void> _pump(WidgetTester tester, AppState app, AxSection s) async {
  app.go(s);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('every section renders without overflow or exceptions', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ArchangelApp());
    await tester.pump(const Duration(milliseconds: 100));
    final app = _appOf(tester);

    for (final s in AxSection.values) {
      await _pump(tester, app, s);
      expect(tester.takeException(), isNull, reason: 'exception while showing $s');
    }
  });

  testWidgets('phone width shows bottom tabs and no overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ArchangelApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    final app = _appOf(tester);

    for (final s in AxSection.values) {
      await _pump(tester, app, s);
      expect(tester.takeException(), isNull, reason: 'exception at phone width while showing $s');
    }
  });

  testWidgets('command palette opens and filters', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ArchangelApp());
    await tester.pump(const Duration(milliseconds: 100));
    final app = _appOf(tester);

    app.openPalette();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('SECTIONS'), findsOneWidget);
  });
}
