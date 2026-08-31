import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A settings list must never show two lit rows at once.
///
/// Under the Spotlight look a lit row inverts to a solid white plate, so a row
/// that keeps its lit state after focus has left does not read as a stale
/// highlight — it reads as a second cursor, and the user cannot tell which row
/// OK will open.
void main() {
  /// Rows currently painting themselves as focused.
  int litRows(WidgetTester tester) => tester
      .widgetList<ParallaxFocus>(find.byType(ParallaxFocus))
      .where((p) => p.focused)
      .length;

  Future<void> pump(WidgetTester tester, Widget body) async {
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) =>
            AppThemeScope(theme: theme, child: child!),
        home: Scaffold(body: body),
      ),
    );
    await tester.pump();
  }

  testWidgets('stepping focus down a section leaves exactly one row lit',
      (tester) async {
    await pump(
      tester,
      SettingsSection(
        title: 'Home',
        children: [
          SettingsTile(
            icon: Icons.dashboard_rounded,
            title: 'Home Layout',
            subtitle: 'Spotlight',
            onTap: () async {},
          ),
          SettingsTile(
            icon: Icons.grid_view_rounded,
            title: 'Home Rows',
            subtitle: 'Choose and arrange',
            onTap: () async {},
          ),
          SettingsTile(
            icon: Icons.slideshow_rounded,
            title: 'Hero Source',
            subtitle: 'Surprise me',
            onTap: () async {},
          ),
        ],
      ),
    );

    // Walk the whole section the way a remote does.
    for (var step = 0; step < 3; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(litRows(tester), 1, reason: 'after $step step(s)');
    }
  });

  testWidgets('a row that opened a route is not still lit after focus moves on',
      (tester) async {
    // The reported case: open a row, come back, carry on down the list. The
    // row that was opened kept its plate.
    final navKey = GlobalKey<NavigatorState>();
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) =>
            AppThemeScope(theme: theme, child: child!),
        home: Scaffold(
          body: SettingsSection(
            title: 'Home',
            children: [
              SettingsTile(
                icon: Icons.dashboard_rounded,
                title: 'Home Layout',
                subtitle: 'Spotlight',
                onTap: () async {},
              ),
              SettingsTile(
                icon: Icons.grid_view_rounded,
                title: 'Home Rows',
                subtitle: 'Choose and arrange',
                onTap: () async {
                  await navKey.currentState!.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('manager')),
                    ),
                  );
                },
              ),
              SettingsTile(
                icon: Icons.slideshow_rounded,
                title: 'Hero Source',
                subtitle: 'Surprise me',
                onTap: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Focus the middle row and open it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.tap(find.text('Home Rows'));
    await tester.pumpAndSettle();
    expect(find.text('manager'), findsOneWidget);

    // Back, then carry on down the list.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(litRows(tester), 1);
  });

  testWidgets('wide Connections routes IPTV down through Tracking', (
    tester,
  ) async {
    ConnectionInfo connection(String title) => ConnectionInfo(
      title: title,
      connected: true,
      status: 'Active',
      caption: 'Ready',
      onTap: () async {},
    );

    await pump(
      tester,
      SingleChildScrollView(
        child: SizedBox(
          width: 800,
          child: ConnectionsSummary(
            realDebrid: connection('Real Debrid'),
            torbox: connection('Torbox'),
            premiumize: connection('Premiumize'),
            allDebrid: connection('AllDebrid'),
            pikpak: connection('PikPak'),
            webDav: connection('WebDAV'),
            indexerManagers: connection('Indexer Managers'),
            iptv: connection('IPTV'),
            tracking: connection('Tracking'),
            trakt: connection('Trakt'),
            simkl: connection('Simkl'),
            mdblist: connection('MDBList'),
          ),
        ),
      ),
    );

    final iptv = tester
        .widgetList<ConnectionCard>(find.byType(ConnectionCard))
        .singleWhere((card) => card.info.title == 'IPTV');
    iptv.focusNode!.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(iptv.focusNode));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings-tracking');
  });
}
