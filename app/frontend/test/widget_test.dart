import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  testWidgets('App shell renders the Overview screen by default', (WidgetTester tester) async {
    await pumpAppShell(tester);

    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Archangel'), findsOneWidget);
  });
}
