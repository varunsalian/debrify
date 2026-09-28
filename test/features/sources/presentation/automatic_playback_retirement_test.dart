import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/source_acquisition_test.dart' as fixture;

class Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  final removed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      removed.add(route);
}

void main() {
  testWidgets(
    'retired automatic acquisition dismisses its loader without popping a newer route',
    (tester) async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      SecretVault.debugReset(deviceIdOverride: 'automatic-playback-retirement');
      SharedPreferences.setMockInitialValues({
        'real_debrid_api_key': 'fixture',
      });
      addTearDown(() {
        ProfileRuntime.debugReset();
        SecretVault.debugReset();
      });
      final nav = GlobalKey<NavigatorState>();
      final routes = Routes();
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [routes],
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: Builder(
              builder: (context) {
                page = context;
                return const Scaffold(body: Text('Origin'));
              },
            ),
          ),
        ),
      );
      late Completer<void> entered;
      late Completer<void> release;
      late Future<void> playback;
      var requests = 0;
      await tester.runAsync(() async {
        entered = Completer<void>();
        release = Completer<void>();
        final client = MockClient((_) async {
          requests++;
          entered.complete();
          await release.future;
          return http.Response('{"id":"retired"}', 201);
        });
        addTearDown(client.close);
        playback = http.runWithClient(
          () => TorrentPlaybackService.playBest(page, [
            fixture.torrent,
          ], provider: 'debrid'),
          () => client,
        );
        await entered.future;
      });
      await tester.pump();
      final loader = routes.pushed.whereType<RawDialogRoute<void>>().single;
      unawaited(
        nav.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('New route')),
          ),
        ),
      );
      await tester.pump();
      ProfileSessionMemory.clearAll();
      await tester.runAsync(() async {
        release.complete();
        await playback;
      });
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(routes.removed, contains(loader));
      expect(find.text('New route'), findsOneWidget);
      expect(routes.pushed.last.isCurrent, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
