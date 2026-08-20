import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/screens/settings/profile_appearance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('profile picker layouts live in Appearance and persist', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileGateStyle.cached = ProfileGateStyle.defaultStyle;

    await tester.pumpWidget(const MaterialApp(home: ProfileAppearancePage()));
    await tester.pumpAndSettle();

    for (final option in ProfileGateStyle.options) {
      expect(find.text(option.label), findsOneWidget);
    }

    await tester.tap(find.text('Theater'));
    await tester.pumpAndSettle();
    expect(ProfileGateStyle.cached, ProfileGateStyle.theater);
  });
}
