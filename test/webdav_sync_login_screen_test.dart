import 'package:debrify/screens/webdav_sync/webdav_sync_login_screen.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_connect_controller.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  Future<void> pumpLogin(
    WidgetTester tester,
    WebDavSyncLoginInspector inspect,
  ) async {
    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) => AppThemeScope(theme: theme, child: child!),
        home: WebDavSyncLoginScreen(inspect: inspect),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );

  Future<void> chooseCustom(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('webdav-sync-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
  }

  testWidgets('Koofr hides URL and explains its app password', (tester) async {
    await pumpLogin(tester, (_) async => null);

    expect(find.byKey(const ValueKey('webdav-sync-url')), findsNothing);
    expect(
      find.textContaining('Koofr → Settings → Password → App passwords'),
      findsOneWidget,
    );
    expect(find.text('Koofr email'), findsOneWidget);
  });

  testWidgets('provider switch shows custom URL and explicit HTTP warning', (
    tester,
  ) async {
    await pumpLogin(tester, (_) async => null);
    await chooseCustom(tester);

    expect(find.byKey(const ValueKey('webdav-sync-url')), findsOneWidget);
    await tester.enterText(field('webdav-sync-url'), 'http://example.test/dav');
    await tester.pump();

    expect(
      find.textContaining('sends your WebDAV password without transport'),
      findsOneWidget,
    );
  });

  testWidgets('Koofr pins its endpoint and auth failures stay generic', (
    tester,
  ) async {
    WebDavSyncLoginCredentials? inspected;
    await pumpLogin(tester, (credentials) async {
      inspected = credentials;
      throw const WebDavException(
        kind: WebDavErrorKind.authentication,
        message: 'provider body containing secret details',
      );
    });

    await tester.enterText(field('webdav-sync-username'), 'alice@example.test');
    await tester.enterText(field('webdav-sync-password'), 'app-password');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(inspected?.endpoint, Uri.parse('https://app.koofr.net/dav/Koofr/'));
    expect(inspected?.serverName, 'Koofr');
    expect(
      find.text('WebDAV login failed. Check your username and password.'),
      findsOneWidget,
    );
    expect(find.textContaining('provider body'), findsNothing);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
}
