import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sync chevron inherits the focused inverse ink', (tester) async {
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) => AppThemeScope(theme: theme, child: child!),
        home: Scaffold(
          body: SettingsTile(
            icon: Icons.sync_rounded,
            title: 'Sync and Migrate',
            subtitle: 'WebDAV',
            trailing: const WebDavSyncPendingBadge(),
            onTap: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final chevron = tester.widget<Icon>(
      find.byIcon(Icons.chevron_right_rounded),
    );
    expect(chevron.color, theme.inkOn(theme.core.tx).withValues(alpha: 0.42));
  });
}
