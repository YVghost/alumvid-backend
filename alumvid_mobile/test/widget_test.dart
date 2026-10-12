import 'package:flutter_test/flutter_test.dart';
import 'package:alumvid_mobile/main.dart';

void main() {
  testWidgets('AlumVid smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AlumVidApp());
    expect(find.text('ALUMVID LOGISTICA'), findsOneWidget);
  });
}
