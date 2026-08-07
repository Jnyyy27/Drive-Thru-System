import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drive_thru_frontend/main.dart';

void main() {
  testWidgets('renders drive thru shell', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const MyApp());

    expect(find.text('Drive Thru Console'), findsOneWidget);
    expect(find.text('API Base URL'), findsOneWidget);
  });
}
