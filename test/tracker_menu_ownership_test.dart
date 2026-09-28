import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final requests = <http.Request>[];
  setUp(() async {
    requests.clear();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'tracker-menu-fixture');
    SharedPreferences.setMockInitialValues({});
    await StorageService.setTraktAccessToken('fixture');
    await StorageService.setSimklAccessToken('fixture');
    await StorageService.saveMdblistApiKey('fixture');
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });
  for (final provider in ['trakt', 'simkl', 'mdblist', 'collection', 'list']) {
    for (final retirement in ['none', 'view', 'session']) {
      testWidgets('$provider modal return ownership: $retirement', (
        tester,
      ) async {
        var current = true;
        Future<void>? pending;
        const item = StremioMeta(id: 'tt123', name: 'Fixture', type: 'series');
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () {
                        pending = switch (provider) {
                          'trakt' => handleTraktMenuAction(
                            context,
                            item,
                            TraktItemMenuAction.rate,
                            isCurrent: () => current,
                          ),
                          'list' => handleTraktMenuAction(
                            context,
                            item,
                            TraktItemMenuAction.addToList,
                            isCurrent: () => current,
                          ),
                          'simkl' => handleSimklMenuAction(
                            context,
                            item,
                            SimklItemMenuAction.rate,
                            isCurrent: () => current,
                          ),
                          'collection' => handleMdblistMenuAction(
                            context,
                            item,
                            MdblistItemMenuAction.addToCollection,
                            isCurrent: () => current,
                          ),
                          _ => handleMdblistMenuAction(
                            context,
                            item,
                            MdblistItemMenuAction.rate,
                            isCurrent: () => current,
                          ),
                        };
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            );
            await tester.runAsync(() async {
              await tester.tap(find.text('Open'));
              await Future<void>.delayed(const Duration(milliseconds: 30));
            });
            await tester.pumpAndSettle();
            if (retirement == 'view') current = false;
            if (retirement == 'session') ProfileSessionMemory.clearAll();
            await tester.runAsync(() async {
              await tester.tap(
                provider == 'mdblist'
                    ? find.widgetWithText(FilledButton, '8')
                    : find.text(
                        provider == 'collection'
                            ? 'Collect'
                            : provider == 'list'
                            ? 'Fixture list'
                            : '8',
                      ),
              );
              await pending!.timeout(const Duration(seconds: 5));
            });
            await tester.pumpAndSettle();
            expect(
              requests.where((r) => r.method == 'POST').length,
              retirement == 'none' ? 1 : 0,
            );
            expect(
              find.byType(SnackBar),
              retirement == 'none' ? findsOneWidget : findsNothing,
            );
          },
          () => MockClient((request) async {
            requests.add(request);
            return http.Response(
              request.method == 'GET'
                  ? '[{"name":"Fixture list","ids":{"slug":"fixture"},"item_count":1}]'
                  : '{}',
              200,
            );
          }),
        );
      });
    }
  }
  testWidgets('accepted menu operation retains its originating scope', (
    tester,
  ) async {
    final origin = ProfileScope(
      profileId: 'origin',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final other = ProfileScope(
      profileId: 'other',
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(origin);
    final release = Completer<void>();
    final scopes = <ProfileScope>[];
    Future<void>? pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                pending = handleSimklMenuAction(
                  context,
                  const StremioMeta(
                    id: 'tt123',
                    name: 'Fixture',
                    type: 'movie',
                  ),
                  SimklItemMenuAction.removeFromContinueWatching,
                  removeContinueWatching: () async {
                    scopes.add(ProfileRuntime.capture());
                    await release.future;
                    scopes.add(ProfileRuntime.capture());
                    return true;
                  },
                );
              },
              child: const Text('Remove'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Remove'));
    expect(scopes, [origin]);
    ProfileSessionMemory.clearAll();
    ProfileRuntime.publish(other);
    release.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(scopes, [origin, origin]);
    expect(find.byType(SnackBar), findsNothing);
  });
}
