import 'package:flutter_test/flutter_test.dart';
import 'package:glassflow_mobile/main.dart';

void main() {
  testWidgets('GlassFlow smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GlassFlowApp());
    expect(find.text('GLASSFLOW LOGISTICA'), findsOneWidget);
  });
}
