import 'dart:async';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/widgets/provider_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Torrent source({bool direct = false, bool hasMagnet = true}) => Torrent(
  rowid: 0,
  hasRealInfoHash: hasMagnet,
  infohash: direct ? 'url:fixture' : 'fixture',
  name: 'Fixture',
  source: direct ? 'stremio:test' : 'test',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: direct ? StreamType.directUrl : StreamType.torrent,
  directUrl: direct ? 'https://example.test/signed' : null,
  stremioAddonId: direct ? 'addon' : null,
  stremioAddonKey: direct ? 'configuration' : null,
  stremioStreamKey: direct ? 'profile' : null,
);

void main() {
  testWidgets('retired direct authorization cannot save or show success', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    var active = true;
    var saves = 0;
    final pending = const SourceBindingBridge().pin(
      context,
      source(direct: true),
      imdbId: 'tt1',
      isMovie: true,
      canContinue: () => active,
      saveBinding: (_) async {
        saves++;
        return true;
      },
    );
    // Direct authorization crosses an async boundary even for ordinary addons.
    active = false;
    expect(await pending, isFalse);
    await tester.pump();
    expect(saves, 0);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final retirement in ['before_choice', 'queued_write', 'none']) {
    final remainsActive = retirement == 'none';
    testWidgets(
      remainsActive
          ? 'active provider dialog retains its remembered choice on pin failure'
          : retirement == 'queued_write'
          ? 'provider choice queued before retirement cannot persist afterward'
          : 'retired provider dialog cannot remember a choice or begin pinning',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (value) {
                context = value;
                return const Scaffold();
              },
            ),
          ),
        );
        var active = true;
        var saves = 0;
        late Future<bool> pending;
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({
            'real_debrid_api_key': 'fixture-rd',
            'torbox_api_key': 'fixture-tb',
          });
          pending = const SourceBindingBridge().pin(
            context,
            source(hasMagnet: false),
            imdbId: 'tt1',
            isMovie: true,
            canContinue: () => active,
            saveBinding: (_) async {
              saves++;
              return true;
            },
          );
        });
        for (
          var i = 0;
          i < 100 && find.text('Remember my choice').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Remember my choice'), findsOneWidget);
        late Completer<void> release;
        late Future<void> snapshot;
        if (retirement == 'queued_write') {
          await tester.runAsync(() async {
            final entered = Completer<void>();
            release = Completer<void>();
            snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
              entered.complete();
              await release.future;
            });
            await entered.future;
          });
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
        }
        active = retirement != 'before_choice';
        Navigator.of(context).pop(const ProviderPickResult('torbox', true));
        await tester.pumpAndSettle();
        if (retirement == 'queued_write') {
          await tester.runAsync(() async {
            // Drain dialog completion and preference opening up to the barrier.
            await Future<void>.delayed(Duration.zero);
            active = false;
            release.complete();
            await snapshot;
          });
        }
        expect(await tester.runAsync(() => pending), isFalse);
        await tester.pump();
        final prefs = await tester.runAsync(SharedPreferences.getInstance);
        expect(
          prefs!.getString('default_torrent_provider_v1'),
          remainsActive ? 'torbox' : null,
        );
        expect(saves, 0);
        expect(
          find.byType(SnackBar),
          remainsActive ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
