import 'package:flutter_test/flutter_test.dart';
import 'package:alumvid_admin_desktop/main.dart';

void main() {
  testWidgets('Smoke test de inicialización AlumVidAdminApp', (WidgetTester tester) async {
    await tester.pumpWidget(const AlumVidAdminApp());
    expect(find.text('AlumVid — Centro de Control'), findsOneWidget);
  });
}
