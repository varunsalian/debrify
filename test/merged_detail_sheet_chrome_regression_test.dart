import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

/// Regression pin for the D2 correction: the MDBList quick-actions sheet must
/// open with the same chrome as the Trakt and Simkl sheets (themed surface,
/// drag handle, scroll-controlled). The extraction commit dropped those three
/// arguments; this test fails on that commit and passes on the origin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => HttpOverrides.global = _CannedNet());
  tearDown(() => HttpOverrides.global = null);

  testWidgets('the MDBList sheet keeps the themed sheet chrome', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppStylePrefs.setDetailPageStyle('classic');
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppThemeScope(
          theme: AppThemes.legacy,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
        home: MergedDetailScreen(
          item: const StremioMeta(
            id: 'mdblist-chrome',
            type: 'movie',
            name: 'Chrome Movie',
          ),
          addon: StremioAddon(
            id: 'pin-addon',
            name: 'Pin Addon',
            manifestUrl: '',
            baseUrl: '',
          ),
          onResume: (_) async {},
          mdblistMenuOptions: const [
            MdblistMenuOption(
              action: MdblistItemMenuAction.addToWatchlist,
              icon: Icons.circle,
              color: Colors.purple,
              label: 'Add to List',
              caption: 'caption',
            ),
          ],
          mdblistStatusLoader: () async => const MdblistTitleStatus(id: 'm'),
          onMdblistAction: (_) async {},
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    await tester.tap(find.byTooltip('MDBList options'));
    await tester.pumpAndSettle();
    expect(find.text('Add to List'), findsOneWidget);

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    final scope = AppThemeScope.of(tester.element(find.byType(BottomSheet)));
    expect(sheet.showDragHandle, isTrue, reason: 'drag handle');
    expect(sheet.backgroundColor, scope.sheetSurface, reason: 'themed surface');
  });
}

class _CannedNet extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _NoNet();
}

class _NoNet implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      throw const SocketException('no network in this test');

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
