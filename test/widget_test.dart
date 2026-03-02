import 'package:flutter_test/flutter_test.dart';

import 'package:agro_cam/main.dart';

void main() {
  testWidgets('App startup smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AgroCamApp());
    expect(find.text('AgroCam'), findsOneWidget);
  });
}
