import 'dart:async';

import 'package:debrify/services/engine/settings_manager.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/debrify_tv_fixture.dart';
import '../../../../support/debrify_tv_handoff.dart';
import 'debrify_tv_playback_test.dart' show options;

void main() {
  testWidgets('C3 O P1 early launch precedes later held search batch', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      await t.runAsync(() => SettingsManager().setGlobalBatchSize(1));
      final held = Completer<http.Response>();
      var searches = 0;
      var atPush = -1;
      f.onRequest = (r) async {
        if (r.url.host == 'debrify-tv-original.test' && ++searches == 2) {
          return held.future;
        }
        return f.providerResponse(r);
      };
      f.observer.onPlayer = (_) => atPush = searches;
      await f.mount(t);
      await f.quick(t, keywords: 'one,two');
      await f.until(t, () => searches == 2);
      expect(atPush, 1, reason: 'P1 launches before the search loop ends');
      expect(f.observer.players.single.title, 'Original.720p.mkv');
      final response = await f.providerResponse(
        http.Request(
          'GET',
          Uri.parse('https://debrify-tv-original.test/search'),
        ),
      );
      held.complete(response);
      await f.settle(t, frames: 50);
      expect(f.observer.players, hasLength(1));
    });
  });

  testWidgets(
    'C3 O P2 quality fallback uses end-of-search launch and complete ledger',
    (t) async {
      await debrifyTvCase(t, (f) async {
        await t.runAsync(
          () => DebrifyTvStorage.setDebrifyTvFilterQualities(['ultraHd']),
        );
        final held = Completer<http.Response>();
        http.Request? waiting;
        f.onRequest = (r) async {
          if (r.url.path.endsWith('/addMagnet') && waiting == null) {
            waiting = r;
            return held.future;
          }
          return f.providerResponse(r);
        };
        await f.mount(t);
        await f.quick(t);
        await f.until(t, () => waiting != null);
        expect(
          find.textContaining('playing anything available'),
          findsOneWidget,
        );
        held.complete(await f.providerResponse(waiting!));
        await f.until(t, () => f.observer.players.isNotEmpty);
        final expected = options(f, quick: true);
        expected['requestChannelById'] = isNotNull;
        expected['channelDirectory'] = [
          {
            'id': 'original-1',
            'name': 'Original channel 1',
            'channelNumber': 1,
            'isCurrent': false,
          },
          {
            'id': 'original-2',
            'name': 'Original channel 2',
            'channelNumber': 2,
            'isCurrent': false,
          },
        ];
        expectDebrifyTvPlayer(f.observer.players.single, 'P2', expected);
      });
    },
  );

  testWidgets('C3 O one channel removes next-channel and by-id callbacks', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.count = 1;
      await f.mount(t);
      await f.watch(t);
      await f.until(t, () => f.observer.players.isNotEmpty);
      expect(f.observer.players.single.requestNextChannel, isNull);
      expect(f.observer.players.single.requestChannelById, isNull);
    });
  });

  testWidgets('C3 O P5 captured requestMagicNext resolves next queue item', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.cacheKeywords = const [
        ['one'],
        ['two'],
      ];
      await t.runAsync(
        () => SettingsManager().setGlobalBackgroundPrefetchEnabled(false),
      );
      await f.mount(t);
      await f.watch(t);
      await f.until(t, () => f.observer.players.isNotEmpty);
      Map<String, String>? next;
      var done = false;
      final pending = f.observer.players.single.requestMagicNext!().then((v) {
        next = v;
        done = true;
      });
      await f.until(t, () => done);
      await pending;
      expect(next, {
        'url': 'https://streams.test/Original.720p.mkv',
        'title': 'Original.720p.mkv',
      });
      expect(f.rdAdds, 2);
    });
  });

  testWidgets(
    'C1 O unmount during held running prefetch issues no further requests',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.cacheKeywords = const [
          ['one'],
          ['two'],
          ['three'],
        ];
        f.television = true;
        await t.runAsync(() async {
          await ExternalPlayerStorage.setDefaultPlayerMode('external');
          await ExternalPlayerStorage.setPreferredExternalPlayer('custom_app');
          await ExternalPlayerStorage.setCustomExternalPlayerPath(null);
        });
        final held = Completer<http.Response>();
        http.Request? waiting;
        var adds = 0;
        f.onRequest = (r) async {
          if (r.url.path.endsWith('/addMagnet') && ++adds == 2) {
            waiting = r;
            return held.future;
          }
          return f.providerResponse(r);
        };
        int? addsAtPush;
        f.observer.onPlayer = (_) {
          addsAtPush = adds;
        };
        await f.mount(t);
        await f.watch(t);
        await f.until(
          t,
          () => find.text('Opening another player').evaluate().isNotEmpty,
        );
        await f.settle(t, frames: 30);
        expect(
          waiting,
          isNotNull,
          reason: 'P5 starts prefetch before the Flutter push',
        );
        await f.tap(t, find.text('Continue'));
        await f.until(t, () => f.observer.players.isNotEmpty);
        expect(
          addsAtPush,
          2,
          reason: 'P5 starts prefetch before the Flutter push',
        );
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
        held.complete(await f.providerResponse(waiting!));
        await f.settle(t, frames: 80);
        final stopped = f.requests.length;
        await f.settle(t, frames: 50);
        expect(
          f.requests.length,
          stopped,
          reason: 'disposed running prefetch never acquires a later torrent',
        );
        expect(adds, 2);
        expect(
          f.debugMessages.where((m) => m == 'MagicTV: Prefetch stopped.'),
          hasLength(2),
          reason: 'dispose stops its active prefetch as well as playback exit',
        );
      });
    },
  );

  testWidgets('C3 O cached PikPak held preparation honours Cancel', (t) async {
    await debrifyTvCase(t, (f) async {
      await t.runAsync(() => f.provider('pikpak'));
      final held = Completer<http.Response>();
      http.Request? waiting;
      f.onRequest = (r) async {
        if (r.method == 'POST' &&
            r.url.path.endsWith('/drive/v1/files') &&
            waiting == null) {
          waiting = r;
          return held.future;
        }
        return f.providerResponse(r);
      };
      await f.mount(t);
      await f.watch(t);
      await f.until(t, () => waiting != null);
      await f.tap(t, find.text('Cancel'));
      held.complete(await f.providerResponse(waiting!));
      await f.settle(t, frames: 100);
      expect(
        f.observer.players,
        isEmpty,
        reason: 'cached PikPak does not push after held Cancel',
      );
    });
  });

  for (final accept in [false, true]) {
    testWidgets(
      'C3 R/O external notice ${accept ? 'accepted failing launch falls back' : 'declined stops without push'}',
      (t) async {
        await debrifyTvCase(t, (f) async {
          f.television = true;
          await t.runAsync(() async {
            await ExternalPlayerStorage.setDefaultPlayerMode('external');
            await ExternalPlayerStorage.setPreferredExternalPlayer(
              'custom_app',
            );
            await ExternalPlayerStorage.setCustomExternalPlayerPath(null);
          });
          await f.mount(t);
          await f.watch(t);
          await f.until(
            t,
            () => find.text('Opening another player').evaluate().isNotEmpty,
          );
          await f.tap(t, find.text(accept ? 'Continue' : 'Cancel'));
          if (accept) {
            await f.until(t, () => f.observer.players.isNotEmpty);
            expect(
              f.observer.players.single.videoUrl,
              'https://streams.test/Original.720p.mkv',
            );
          } else {
            await f.settle(t, frames: 50);
            expect(
              f.observer.players,
              isEmpty,
              reason: 'declined external notice must not fall through',
            );
            final stopped = f.requests.length;
            await f.settle(t, frames: 30);
            expect(f.requests.length, stopped);
          }
        });
      },
    );
  }
}
