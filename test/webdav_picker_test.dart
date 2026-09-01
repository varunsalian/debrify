import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/webdav_settings_page.dart';
import 'package:debrify/screens/webdav/webdav_files_screen.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _config = WebDavConfig(
  id: 'server',
  name: 'Test server',
  baseUrl: 'https://example.test/dav',
  username: 'alice',
  password: 'secret',
  connectionResourceId: 'resource',
  connectionResourceRevision: 1,
);

class _FakeSource extends WebDavFilesDataSource {
  const _FakeSource([
    this.config = _config,
    ProfileFeature feature = ProfileFeature.cloud,
  ]) : super(feature: feature);

  final WebDavConfig config;

  @override
  Future<List<WebDavConfig>> loadConfigs() async => [config];

  @override
  Future<WebDavConfig?> loadSelectedConfig() async => config;

  @override
  Future<List<WebDavItem>> listDirectory(
    WebDavConfig config,
    String path,
  ) async => const [
    WebDavItem(name: 'Folder', path: 'Folder/', isDirectory: true),
    WebDavItem(
      name: 'debrify-profile.json',
      path: 'debrify-profile.json',
      isDirectory: false,
      sizeBytes: 42,
    ),
    WebDavItem(name: 'movie.mp4', path: 'movie.mp4', isDirectory: false),
  ];

  @override
  Future<void> selectConfig(String id) async {}
}

class _RouteCaptureObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    lastPushed = route;
  }
}

Future<void> _pumpPicker(
  WidgetTester tester,
  WebDavPickerMode mode, {
  WebDavConfig config = _config,
  ProfileFeature feature = ProfileFeature.cloud,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) async {
  final theme = AppThemes.byId('spotlight');
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
      navigatorObservers: navigatorObservers,
      builder: (context, child) => AppThemeScope(theme: theme, child: child!),
      home: WebDavFilesScreen(
        pickerMode: mode,
        dataSource: _FakeSource(config, feature),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('folder picker has an explicit first DPAD action', (
    tester,
  ) async {
    await _pumpPicker(tester, WebDavPickerMode.selectFolder);

    expect(find.text('Choose server root'), findsOneWidget);
    expect(find.text('Folder'), findsWidgets);
    expect(find.text('debrify-profile.json'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'webdav-choose-folder',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup picker exposes folders and JSON packages, not media', (
    tester,
  ) async {
    await _pumpPicker(tester, WebDavPickerMode.selectBackup);

    expect(find.text('Folder'), findsWidgets);
    expect(find.text('debrify-profile.json'), findsOneWidget);
    expect(find.text('movie.mp4'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'webdav-first-item');
    expect(tester.takeException(), isNull);
  });

  testWidgets('migration picker repeats the insecure HTTP warning', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      WebDavPickerMode.selectFolder,
      config: const WebDavConfig(
        id: 'insecure',
        name: 'LAN server',
        baseUrl: 'http://nas.local/dav',
        username: 'alice',
        password: 'secret',
      ),
    );

    expect(find.textContaining('Insecure HTTP:'), findsOneWidget);
  });

  testWidgets('migration picker carries backupRestore into settings', (
    tester,
  ) async {
    final observer = _RouteCaptureObserver();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await _pumpPicker(
      tester,
      WebDavPickerMode.selectFolder,
      feature: ProfileFeature.backupRestore,
      navigatorObservers: <NavigatorObserver>[observer],
    );

    await tester.tap(find.byTooltip('Settings'));
    final route = observer.lastPushed! as MaterialPageRoute<dynamic>;
    final page = route.builder(tester.element(find.byType(WebDavFilesScreen)));
    expect(page, isA<WebDavSettingsPage>());
    expect((page as WebDavSettingsPage).feature, ProfileFeature.backupRestore);
  });
}
