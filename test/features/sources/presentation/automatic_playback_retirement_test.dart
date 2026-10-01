import 'package:debrify/services/main_page_bridge.dart';
import 'dart:io';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:debrify/services/video_player_launcher.dart';
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
          if (entered.isCompleted) return http.Response('', 204);
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
      // The add, then removal of the torrent the retired add abandoned.
      expect(requests, 2);
      expect(routes.removed, contains(loader));
      expect(find.text('New route'), findsOneWidget);
      expect(routes.pushed.last.isCurrent, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'retired launch owner releases handoff once without opening a player',
    (tester) async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      final owner = ProfileSessionMemory.captureOwner();
      final routes = Routes();
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: Builder(
            builder: (context) {
              page = context;
              return const Text('Origin');
            },
          ),
        ),
      );
      ProfileSessionMemory.clearAll();
      var handoffs = 0;
      await VideoPlayerLauncher.push(
        page,
        const VideoPlayerLaunchArgs(
          videoUrl: 'https://example.test/movie.mp4',
          title: 'Movie',
        ),
        sourceOwner: owner,
        onPlayerHandoff: () {
          handoffs++;
        },
      );
      expect(handoffs, 1);
      expect(routes.pushed, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  for (final afterDispatch in [false, true]) {
    testWidgets(
      'external handoff rejects stale follow-up afterDispatch=$afterDispatch',
      (tester) async {
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        SharedPreferences.setMockInitialValues({});
        addTearDown(ProfileRuntime.debugReset);
        await StorageService.setDefaultPlayerMode('external');
        await StorageService.setPreferredExternalPlayer('infuse');
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        var launches = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              launches++;
              if (afterDispatch) ProfileSessionMemory.clearAll();
              return true;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        late BuildContext page;
        final routes = Routes();
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [routes],
            home: Builder(
              builder: (context) {
                page = context;
                return const Scaffold(body: Text('Origin'));
              },
            ),
          ),
        );
        final owner = ProfileSessionMemory.captureOwner();
        var returns = 0;
        void returned() {
          returns++;
        }

        MainPageBridge.addPlaybackReturnListener(returned);
        addTearDown(
          () => MainPageBridge.removePlaybackReturnListener(returned),
        );
        var handoffs = 0;
        final launch = VideoPlayerLauncher.push(
          page,
          VideoPlayerLaunchArgs(
            videoUrl: afterDispatch
                ? 'https://example.test/movie.mp4'
                : 'https://example.test/movie.mp4?token=fixture',
            title: 'Movie',
          ),
          sourceOwner: owner,
          onPlayerHandoff: () {
            handoffs++;
          },
        );
        await tester.pumpAndSettle();
        if (!afterDispatch) {
          expect(find.text('Share stream with another app?'), findsOneWidget);
          ProfileSessionMemory.clearAll();
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
        }
        await launch;
        expect(launches, afterDispatch ? 1 : 0);
        expect(handoffs, 1);
        expect(
          routes.pushed,
          hasLength(afterDispatch ? 1 : 2),
        ); // No player route.
        if (afterDispatch) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          expect(returns, 1);
          // Consume the existing return-observer timeout in fake time.
          await tester.pump(const Duration(seconds: 31));
          expect(returns, 1);
        }
        expect(tester.takeException(), isNull);
      },
      skip: afterDispatch && !Platform.isMacOS,
    );
  }
}
