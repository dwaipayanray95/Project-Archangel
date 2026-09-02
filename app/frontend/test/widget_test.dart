import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/main.dart';

void main() {
  testWidgets('App shell renders the Overview screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(const ArchangelApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Archangel'), findsOneWidget);
  });
}
