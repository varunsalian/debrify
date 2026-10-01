import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'simkl-dialog-fixture');
    SharedPreferences.setMockInitialValues({});
    await SimklStorage.setSimklAccessToken('fixture');
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });
  testWidgets('retired rating dialog cannot submit a mutation', (tester) async {
    var current = true, requests = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => handleSimklMenuAction(
                    context,
                    StremioMeta(id: 'tt123', name: 'Fixture', type: 'movie'),
                    SimklItemMenuAction.rate,
                    isCurrent: () => current,
                  ),
                  child: const Text('Rate'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Rate'));
        await tester.pumpAndSettle();
        expect(find.text('Rate this item'), findsOneWidget);
        current = false;
        await tester.tap(find.text('8'));
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(find.byType(SnackBar), findsNothing);
      },
      () => MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
  });
  for (final series in [false, true]) {
    for (final result in [true, false, null]) {
      testWidgets('removal feedback series=$series result=$result', (
        tester,
      ) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => handleSimklMenuAction(
                    context,
                    StremioMeta(
                      id: 'tt123',
                      name: 'Fixture',
                      type: series ? 'series' : 'movie',
                    ),
                    SimklItemMenuAction.removeFromContinueWatching,
                    removeContinueWatching: () async {
                      calls++;
                      return result;
                    },
                  ),
                  child: const Text('Remove'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        if (result == null) {
          expect(find.byType(SnackBar), findsNothing);
        } else {
          final label = series
              ? 'Removed — moved to On Hold on Simkl'
              : 'Removed from Continue Watching';
          expect(find.text(result ? label : 'Failed: $label'), findsOneWidget);
        }
      });
    }
  }
  testWidgets('retirement during removal suppresses feedback', (tester) async {
    var current = true;
    final pending = Completer<bool?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => handleSimklMenuAction(
                context,
                StremioMeta(id: 'tt123', name: 'Fixture', type: 'movie'),
                SimklItemMenuAction.removeFromContinueWatching,
                isCurrent: () => current,
                removeContinueWatching: () => pending.future,
              ),
              child: const Text('Remove'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Remove'));
    current = false;
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
