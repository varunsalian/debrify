import 'dart:async';

import 'package:debrify/features/sources/application/source_binding_dependencies.dart';
import 'package:debrify/features/sources/data/source_acquisition.dart';
import 'package:debrify/features/sources/models/acquired_source.dart';
import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HeldAcquisition extends SourceAcquisition {
  final requested = Completer<void>();
  final result = Completer<AcquiredSource>();
  String? provider;
  String? magnet;
  bool Function()? guard;

  @override
  Future<AcquiredSource> acquire(
    String provider,
    String magnet,
    Torrent torrent, {
    bool Function()? canContinue,
  }) {
    this.provider = provider;
    this.magnet = magnet;
    guard = canContinue;
    requested.complete();
    return result.future;
  }
}

void main() {
  tearDown(SecretVault.debugReset);
  for (final outcome in ['ready', 'retired', 'failed']) {
    testWidgets('provider override reaches manual pin with $outcome result', (
      tester,
    ) async {
      final acquisition = (await tester.runAsync(
        () async => HeldAcquisition(),
      ))!;
      late BuildContext context;
      late SourceBindingBridge bridge;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sourceAcquisitionProvider.overrideWithValue(acquisition)],
          child: MaterialApp(
            home: Consumer(
              builder: (value, ref, _) {
                context = value;
                bridge = ref.read(sourceBindingBridgeProvider);
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      var active = true;
      bool? accepted;
      final writes = <SeriesSource>[];
      await tester.runAsync(() async {
        SecretVault.debugReset(deviceIdOverride: 'acquisition-di');
        SharedPreferences.setMockInitialValues({
          'pikpak_enabled': true,
          'pikpak_email': 'fixture@example.test',
        });
        final pending = bridge.pin(
          context,
          Torrent(
            rowid: 0,
            infohash: 'fixture',
            name: 'Fixture',
            sizeBytes: 1,
            createdUnix: 0,
            seeders: 0,
            leechers: 0,
            completed: 0,
            scrapedDate: 0,
          ),
          imdbId: 'tt1234567',
          isMovie: true,
          canContinue: () => active,
          saveBinding: (source) async {
            writes.add(source);
            return true;
          },
        );
        await acquisition.requested.future.timeout(const Duration(seconds: 5));
        expect(acquisition.provider, 'pikpak');
        expect(acquisition.magnet, 'magnet:?xt=urn:btih:fixture&dn=Fixture');
        expect(acquisition.guard!(), isTrue);
        if (outcome == 'retired') active = false;
        if (outcome == 'failed') {
          acquisition.result.completeError(StateError('Provider failed'));
        } else {
          acquisition.result.complete(
            const AcquiredSource(
              title: 'Fixture',
              playUrl: 'https://fixture.test/video',
            ),
          );
        }
        accepted = await pending;
      });
      await tester.pumpAndSettle();
      expect(accepted, outcome == 'ready');
      expect(writes, hasLength(outcome == 'ready' ? 1 : 0));
      if (writes.isNotEmpty) {
        expect(writes.single.debridService, 'pikpak');
        expect(writes.single.torrentHash, 'fixture');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
