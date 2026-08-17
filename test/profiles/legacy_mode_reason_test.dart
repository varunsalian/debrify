import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The legacy-mode row is the whole bug report a TV user can give — a phone
/// photo of the settings screen. These pin that the captured reason actually
/// reaches that photo: the summary feeds the row, and the dialog shows the
/// reason in full with a DPAD-reachable dismiss.
void main() {
  tearDown(() => ProfileBootstrap.legacyReason = null);

  test('summary falls back to the generic line when nothing was captured', () {
    ProfileBootstrap.legacyReason = null;
    expect(
      ProfileBootstrap.legacyReasonSummary,
      'This install is running in legacy mode',
    );
  });

  test('summary is the captured reason verbatim', () {
    ProfileBootstrap.legacyReason =
        'Migration failed — StateError: no disposition for key x';
    expect(
      ProfileBootstrap.legacyReasonSummary,
      'Migration failed — StateError: no disposition for key x',
    );
  });

  testWidgets('the dialog shows the full reason and OK dismisses it', (
    tester,
  ) async {
    ProfileBootstrap.legacyReason =
        'Migration failed — StateError: database integrity check failed\n'
        'at #0 ProfileMigrationService.migrate (profile_migration_service.dart:1)';

    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) => AppThemeScope(theme: theme, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLegacyModeInfoDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The diagnosis, in full — stack frame included.
    expect(
      find.textContaining('database integrity check failed'),
      findsOneWidget,
    );
    expect(
      find.textContaining('ProfileMigrationService.migrate'),
      findsOneWidget,
    );
    // The reassurance is load-bearing: legacy mode looks like data loss.
    expect(find.textContaining('Your data is untouched'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Running in legacy mode'), findsNothing);
  });
}
