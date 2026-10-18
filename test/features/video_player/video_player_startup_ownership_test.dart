import 'dart:async';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../sources/data/source_acquisition_test.dart' as acquisition;
import 'support/local_completion_driver.dart';
import 'support/startup_driver.dart';
import 'support/startup_ownership_driver.dart';
import 'support/trakt_transport.dart';

void main() {
  TraktTestTransport.install();
  for (final stage in ['provider selection', 'acquisition']) {
    for (final crossing in [
      'none',
      'A to B',
      'A to B to A',
      'delete A',
      'route close',
    ]) {
      testWidgets(
        'P16 real source resolver $stage across $crossing preserves captured ownership and both physical stores',
        (t) async {
          final d = StartupOwnershipDriver(t);
          await d.setup();
          final torrent = ownershipSource('incoming-torrent', torrent: true);
          final provider = CompletionDelivery(
            'SourcePlaylistResolver._resolve',
            (v) => v == 'debrid',
          );
          provider.armed = stage == 'provider selection';
          final reply = Completer<void>();
          var requested = false;
          final transport = acquisition.Fixture('debrid', 'single');
          d.f.network.handler = (r) async {
            if (stage == 'acquisition' && r.url.path.endsWith('/addMagnet')) {
              requested = true;
              await reply.future;
            }
            // The shared pure-service fixture uses guarded expect() inside
            // its 204 arm. Widget pumping may deliver this response while a
            // test API is guarded; assert these paths after delivery instead.
            if (r.url.path.endsWith('/selectFiles/owned') ||
                r.url.path.endsWith('/delete/owned')) {
              transport.paths.add(r.url.path);
              transport.requests.add(r);
              return http.Response('', 204);
            }
            return transport.respond(r);
          };
          try {
            if (stage == 'acquisition') await d.credential();
            await d.start(
              lazy: stage == 'provider selection',
              sources: [d.first, torrent],
            );
            final aBefore = await d.physical(d.origin);
            final bBefore = await d.physical(d.incoming);
            if (stage == 'provider selection') await d.credential();
            expect(d.bindings.isCurrent, isTrue);
            final sheet = await d.sheet();
            final resolution = d.f.actions.start(
              'real production playlist resolver',
              () => d.observeErrors(
                () => provider.run(() => sheet.resolveSource(torrent)),
              ),
              held: true,
            );
            await d.f.until(
              t,
              () => stage == 'provider selection'
                  ? provider.pending.isNotEmpty
                  : requested,
            );
            expect(resolution.isCompleted, isFalse);
            expect(d.opens, [d.first.directUrl]);
            await d.crossing(crossing);
            if (crossing != 'none' && crossing != 'route close') {
              expect(d.bindings.isCurrent, isFalse);
            }
            provider.release();
            reply.completeIfPending();
            if (crossing == 'none') {
              await d.f.until(
                t,
                () => transport.paths.any(
                  (p) => p.endsWith('/selectFiles/owned'),
                ),
              );
              await d.tick();
              await d.tick(const Duration(milliseconds: 2100));
            }
            final resolved = await d.f.finish(t, resolution.future);
            if (crossing == 'none') {
              expect(
                resolved,
                'https://stream.test/2',
                reason:
                    'paths=${transport.paths}; deliveries=${provider.values}; owner=${d.bindings.isCurrent}; route=${d.launch!.isCompleted}; errors=${d.caught}',
              );
              expect(
                transport.paths,
                contains('/rest/1.0/torrents/selectFiles/owned'),
              );
              expect(d.caught, isEmpty);
              final selected = d.select(sheet, 1, resolved!);
              await d.f.finish(t, selected.future);
              await d.f.until(
                t,
                () => d.store.writes.any(
                  (v) =>
                      v.$1.endsWith('series_source_$ownershipId') &&
                      (v.$2 as String).contains(torrent.infohash),
                ),
              );
              expect(await d.pins(d.origin), contains(torrent.infohash));
              expect(await d.cache(d.origin), aBefore['cache']);
              expect(d.opens, [d.first.directUrl, 'https://stream.test/2']);
            } else {
              expect(resolved, isNull);
              expect(d.opens, [d.first.directUrl]);
              expect(await d.physical(d.origin), aBefore);
              if (stage == 'provider selection') {
                expect(
                  transport.requests,
                  isEmpty,
                  reason:
                      'Retirement before provider delivery prevents acquisition',
                );
              }
            }
            expect(await d.physical(d.incoming), bBefore);
            expect(bBefore['binding'], '');
            expect(bBefore['cache'], '');
            expect(bBefore['sentinel'], 'incoming-untouched');
          } finally {
            provider.release();
            reply.completeIfPending();
            await d.close();
          }
        },
      );
    }
  }

  for (final stage in ['before cache write', 'admitted physical write']) {
    for (final crossing in [
      'none',
      'A to B',
      'A to B to A',
      'delete A',
      'route close',
    ]) {
      testWidgets(
        'P16 real queued binding commits $stage across $crossing preserve retirement versus admitted outgoing writes',
        (t) async {
          final d = StartupOwnershipDriver(t);
          await d.setup();
          final gate = Completer<void>();
          final entered = Completer<void>();
          final completions = CompletionDelivery(
            'commitValidatedStremioSource',
            (v) => v == null,
          );
          completions.multiple = true;
          completions.armed = false;
          Future<void>? snapshot;
          try {
            await d.credential();
            await d.start();
            final aBefore = await d.physical(d.origin);
            final bBefore = await d.physical(d.incoming);
            if (stage == 'before cache write') {
              snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
                entered.complete();
                await gate.future;
              });
              await d.f.until(t, () => entered.isCompleted);
            } else {
              d.store.gate = gate;
              d.store.armed = true;
            }
            completions.armed = true;
            final sheet = await d.sheet();
            final second = d.second.directUrl!;
            final firstAction = completions.run(
              () => d.select(sheet, 1, second),
            );
            await d.f.finish(t, firstAction.future);
            if (stage == 'admitted physical write') {
              await d.f.until(t, () => d.store.entered);
            }
            expect(
              completions.pending,
              isEmpty,
              reason:
                  'The caller commit remains suspended behind its real persistence boundary',
            );
            expect(await d.cache(d.origin), aBefore['cache']);
            final next = await d.sheet();
            final third = d.third.directUrl!;
            final secondAction = completions.run(
              () => d.select(next, 2, third),
            );
            await d.f.finish(t, secondAction.future);
            expect(d.opens, [
              d.first.directUrl,
              d.second.directUrl,
              d.third.directUrl,
            ]);
            await d.crossing(
              crossing,
              pendingDelete: stage == 'before cache write',
            );
            gate.completeIfPending();
            if (d.deletion != null) await d.f.finish(t, d.deletion!);
            if (snapshot != null) await d.f.finish(t, snapshot);
            await d.f.until(t, () => completions.pending.length == 2);
            expect(await d.physical(d.incoming), bBefore);
            final aAfter = await d.physical(d.origin);
            if (crossing == 'none') {
              expect(aAfter['binding'], contains('third'));
              expect(aAfter['cache'], contains(d.second.directUrl!));
              expect(aAfter['cache'], contains(d.third.directUrl!));
            } else {
              expect(aAfter['binding'], aBefore['binding']);
              expect(aAfter['cache'], isNot(contains(d.third.directUrl!)));
              if (stage == 'admitted physical write') {
                expect(
                  aAfter['cache'],
                  contains(d.second.directUrl!),
                  reason:
                      'The physical setter was already admitted with A arguments before retirement',
                );
              } else {
                expect(
                  aAfter['cache'],
                  aBefore['cache'],
                  reason:
                      'The real mutation barrier rechecks ownership before admitting the setter',
                );
              }
            }
            completions.release();
            await d.settle();
          } finally {
            gate.completeIfPending();
            completions.release();
            if (snapshot != null) await d.f.finish(t, snapshot);
            await d.close();
          }
        },
      );
    }
  }
}
