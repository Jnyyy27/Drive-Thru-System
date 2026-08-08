import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drive_thru_frontend/app.dart';

void main() {
  testWidgets('renders login shell', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Drive Thru Console'), findsOneWidget);
    expect(find.text('Sign In with Cognito'), findsOneWidget);
  });
}
