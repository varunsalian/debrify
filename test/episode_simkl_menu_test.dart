import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalHttp extends HttpOverrides {}

void main() {
  for (final isTelevision in [false, true]) {
    testWidgets(
      'Simkl episode menu keeps watched action without rating (TV=$isTelevision)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        SecretVault.debugReset(deviceIdOverride: 'simkl-menu-test');
        addTearDown(SecretVault.debugReset);
        final show = StremioMeta(
          id: 'simkl-menu-$isTelevision',
          type: 'series',
          name: 'Test Show',
        );
        late StremioAddon addon;
        await tester.runAsync(
          () => HttpOverrides.runWithHttpOverrides(() async {
            // Fake credentials only. A non-IMDb fixture avoids tracker reads;
            // the menu still resolves real auth and watched-destination policy.
            await StorageService.setSimklAccessToken('test-only-token');
            await StorageService.setTrackingScrobbleTargets({
              TrackingSource.simkl,
            });
            expect(await SimklService.instance.isAuthenticated(), isTrue);
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            server.listen((request) async {
              request.response.write(
                jsonEncode({
                  'meta': {
                    'videos': [
                      {'season': 1, 'episode': 1, 'title': 'Pilot'},
                    ],
                  },
                }),
              );
              await request.response.close();
            });
            final base = 'http://127.0.0.1:${server.port}';
            addon = StremioAddon(
              id: 'simkl-menu-$isTelevision',
              name: 'Test',
              baseUrl: base,
              manifestUrl: '$base/manifest.json',
              resources: const ['meta'],
              types: const ['series'],
            );
            try {
              expect(
                await StremioService.instance.fetchSeriesMeta(addon, show.id),
                hasLength(1),
              );
            } finally {
              await server.close(force: true);
            }
          }, _LocalHttp()),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: Scaffold(
                body: EpisodesPanel(
                  show: show,
                  addon: addon,
                  isTelevision: isTelevision,
                  contentBuilder: (context, view) => view.episodes.isEmpty
                      ? const SizedBox()
                      : TextButton(
                          onPressed: () => view.options(view.episodes.single),
                          child: const Text('Episode options'),
                        ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 20; i++) {
          // Credential decryption uses real async work, not the widget clock.
          await tester.runAsync(() => SimklService.instance.isAuthenticated());
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.text('Episode options'));
        await tester.pumpAndSettle();

        expect(find.text('Rate on Simkl'), findsNothing);
        expect(find.text('Mark as Watched'), findsOneWidget);
        expect(find.text('On Simkl and this device'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Sources'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
