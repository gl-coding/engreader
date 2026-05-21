import 'package:flutter_test/flutter_test.dart';
import 'package:engreader/app.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const EngReaderApp());
    expect(find.text('EngReader'), findsOneWidget);
  });
}
