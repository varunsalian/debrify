import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RouteLog extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  for (final change in [
    'route_above',
    'loader_removed',
    'origin_removed',
    'navigator_disposed',
  ]) {
    testWidgets('retired binding cleans only its loader after $change', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final observer = RouteLog();
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold(body: Text('Sources'));
            },
          ),
        ),
      );
      final response = Completer<http.Response>();
      var requested = false;
      var active = true;
      var finished = false;
      var saves = 0;
      bool? result;
      Object? error;
      final client = MockClient((request) {
        requested = true;
        return response.future;
      });
      addTearDown(client.close);
      addTearDown(SecretVault.debugReset);
      await tester.runAsync(() async {
        SecretVault.debugReset(deviceIdOverride: 'loader-fixture');
        SharedPreferences.setMockInitialValues({
          'torbox_api_key': 'fixture-token',
        });
        unawaited(
          http
              .runWithClient(
                () => const SourceBindingBridge().pin(
                  page,
                  Torrent(
                    rowid: 0,
                    infohash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                    name: 'Fixture',
                    sizeBytes: 1024,
                    createdUnix: 0,
                    seeders: 0,
                    leechers: 0,
                    completed: 0,
                    scrapedDate: 0,
                  ),
                  imdbId: 'tt-fixture',
                  isMovie: true,
                  canContinue: () => active,
                  saveBinding: (_) async {
                    saves++;
                    return true;
                  },
                ),
                () => client,
              )
              .then(
                (value) {
                  result = value;
                  finished = true;
                },
                onError: (Object caught) {
                  error = caught;
                  finished = true;
                },
              ),
        );
      });
      for (var attempt = 0; attempt < 100 && !requested; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(requested, isTrue);
      expect(observer.pushed, hasLength(2));
      final loader = observer.pushed.last;
      expect(loader, isA<RawDialogRoute<dynamic>>());
      active = false;
      MaterialPageRoute<void>? incoming;
      if (change == 'navigator_disposed') {
        await tester.pumpWidget(const SizedBox());
      } else {
        if (change == 'loader_removed') {
          navigator.currentState!.removeRoute(loader);
        }
        if (change == 'origin_removed') {
          navigator.currentState!.removeRoute(observer.pushed.first);
        }
        incoming = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Incoming')),
        );
        unawaited(navigator.currentState!.push(incoming));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.runAsync(() async {
        response.complete(
          http.Response(
            jsonEncode({
              'success': true,
              'data': {'torrent_id': 7},
            }),
            200,
          ),
        );
      });
      for (var attempt = 0; attempt < 100 && !finished; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(finished, isTrue);
      expect(error, isNull);
      expect(result, isFalse);
      expect(saves, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(loader.isActive, isFalse);
      if (incoming != null) {
        expect(incoming.isCurrent, isTrue);
        expect(find.text('Incoming'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
