import 'dart:convert';

import 'package:debrify/screens/see_all/mdblist_see_all_screen.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_discover_models.dart';
import 'package:debrify/services/mdblist/mdblist_discover_source.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Catalog makes no query until the user presses Apply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var catalogRequests = 0;
    final service = MdblistService.forTesting(
      client: MockClient((request) async {
        if (request.url.path.startsWith('/catalog/')) {
          catalogRequests++;
          return http.Response(
            jsonEncode({
              'movies': const [],
              'pagination': {'next_cursor': null},
              'quota': {'remaining': 3},
            }),
            200,
          );
        }
        return http.Response('unexpected request', 500);
      }),
      apiKeyProvider: () async => 'test-key',
    );
    final source = MdblistDiscoverSource.forTesting(
      service,
      fetchContinueWatching: ({bool force = false}) async =>
          const MdblistResult.success(MdblistContinueWatchingSnapshot()),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: MdblistSeeAllScreen(
            source: source,
            isAuthenticated: () async => true,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(catalogRequests, 0);

    await tester.tap(find.byType(StremioDropdown<MdblistDiscoverGroup>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catalog').last);
    await tester.pumpAndSettle();

    expect(catalogRequests, 0);
    expect(
      find.text(
        'Choose filters and press Apply — Catalog never runs automatically',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(catalogRequests, 1);
    expect(find.textContaining('3 catalog queries remaining'), findsOneWidget);

    await tester.tap(find.byType(StremioDropdown<MdblistDiscoverGroup>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('Nothing to continue yet'), findsOneWidget);
  });

  testWidgets('changing a Catalog query clears stale items without fetching', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var catalogRequests = 0;
    final service = MdblistService.forTesting(
      client: MockClient((request) async {
        catalogRequests++;
        return http.Response(
          jsonEncode({
            'movies': [
              {
                'imdb_id': 'tt1',
                'title': 'Old Movie Result',
                'mediatype': 'movie',
              },
            ],
            'quota': {'remaining': 3},
          }),
          200,
        );
      }),
      apiKeyProvider: () async => 'test-key',
    );
    final source = MdblistDiscoverSource.forTesting(
      service,
      fetchContinueWatching: ({bool force = false}) async =>
          const MdblistResult.success(MdblistContinueWatchingSnapshot()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: MdblistSeeAllScreen(
            source: source,
            isAuthenticated: () async => true,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(StremioDropdown<MdblistDiscoverGroup>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catalog').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Old Movie Result'), findsWidgets);
    expect(catalogRequests, 1);

    final showDropdown = find.byWidgetPredicate(
      (widget) => widget is StremioDropdown<String> && widget.label == 'Show',
    );
    await tester.tap(showDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Series').last);
    await tester.pumpAndSettle();

    expect(catalogRequests, 1);
    expect(find.text('Old Movie Result'), findsNothing);
    expect(
      find.text(
        'Choose filters and press Apply — Catalog never runs automatically',
      ),
      findsOneWidget,
    );
  });
}
