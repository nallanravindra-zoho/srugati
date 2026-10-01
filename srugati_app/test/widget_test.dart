import 'package:flutter_test/flutter_test.dart';

import 'package:srugati_app/main.dart';

void main() {
  testWidgets('App boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SruGatiApp());
    expect(find.text('SruGati'), findsOneWidget);
  });
}
