import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSheetHost(
    WidgetTester tester, {
    required SimklTitleStatus initialStatus,
    required void Function(SimklItemMenuAction action) onAction,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService.setDetailPageStyle('classic');
    var status = initialStatus;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: MergedDetailScreen(
          item: const StremioMeta(
            id: 'simkl-toggle-movie',
            type: 'movie',
            name: 'Toggle Movie',
          ),
          addon: StremioAddon(
            id: 'simkl-toggle-test',
            name: 'Toggle Test',
            manifestUrl: '',
            baseUrl: '',
          ),
          onResume: (_) async {},
          simklMenuOptions: buildSimklMenuOptions(isSimklAuthenticated: true),
          simklMenuBuilder: (fresh) =>
              buildSimklMenuOptions(isSimklAuthenticated: true, status: fresh),
          simklStatusLoader: () async => status,
          onSimklAction: (action) async {
            onAction(action);
            if (action == SimklItemMenuAction.removeFromList) {
              status = const SimklTitleStatus();
            }
          },
        ),
      ),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byTooltip('Simkl options'));
    await tester.pumpAndSettle();
  }

  testWidgets('active Plan to Watch switch dispatches whole-title removal', (
    tester,
  ) async {
    SimklItemMenuAction? captured;
    await pumpSheetHost(
      tester,
      initialStatus: const SimklTitleStatus(currentStatus: 'plantowatch'),
      onAction: (action) => captured = action,
    );

    expect(find.byType(Switch), findsNWidgets(3));
    final active = tester
        .widgetList<Switch>(find.byType(Switch))
        .singleWhere((toggle) => toggle.value);
    expect(active.value, isTrue);

    await tester.tap(find.text('Plan to Watch').last);
    await tester.pumpAndSettle();

    expect(captured, SimklItemMenuAction.removeFromList);
    expect(
      tester.widgetList<Switch>(find.byType(Switch)).where((s) => s.value),
      isEmpty,
    );
  });

  testWidgets('whole-title confirmation discloses every deleted data type', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmSimklTitleRemoval(context, 'Rated Movie');
            },
            child: const Text('Open confirmation'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open confirmation'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from Simkl?'), findsOneWidget);
    expect(
      find.textContaining(
        'watched history, rating, and saved playback progress',
      ),
      findsOneWidget,
    );
    expect(result, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
