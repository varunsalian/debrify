import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/debrify_tv/widgets/random_start_slider.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/engine/settings_manager.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/debrify_tv_fixture.dart';
import '../../../../support/debrify_tv_handoff.dart';
import 'debrify_tv_import_export_test.dart' show chooseImport, importedYaml;

Future<void> resetChannels(WidgetTester t, DebrifyTvFixture f) async {
  await f.settings(t);
  await f.tap(t, find.text('Reset to defaults'));
  expect(t.widget<RandomStartSlider>(find.byType(RandomStartSlider)).value, 20);
  await f.tap(t, find.text('Done'));
}

Map<String, dynamic> switched(int number) => {
  'channelId': 'original-$number',
  'firstUrl': 'https://streams.test/Original.720p.mkv',
  'firstTitle': 'Original.720p.mkv',
  'channelName': 'Original channel $number',
  'channelNumber': number,
};

void main() {
  for (final flow in [
    ('real_debrid', 'P1', true),
    ('real_debrid', 'P2', true),
    ('torbox', 'P3', true),
    ('pikpak', 'P4', true),
    ('real_debrid', 'P5', false),
    ('alldebrid', 'P6', false),
    ('torbox', 'P7', false),
    ('pikpak', 'P8', false),
    ('premiumize', 'P10', false),
    ('premiumize', 'P11', true),
    ('alldebrid', 'P12', true),
  ]) {
    testWidgets(
      '0b O ${flow.$2} distinguishes channel and copied quick options',
      (t) async {
        await debrifyTvCase(t, (f) async {
          f.style = 'spotlight';
          await t.runAsync(() async {
            await f.provider(flow.$1);
            await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
            if (flow.$2 == 'P2') {
              await DebrifyTvStorage.setDebrifyTvFilterQualities(['ultraHd']);
            }
          });
          final held = Completer<http.Response>();
          http.Request? waiting;
          f.onRequest = (r) async {
            if (waiting == null &&
                (flow.$2 != 'P2' || r.url.path.endsWith('/addMagnet'))) {
              waiting = r;
              return held.future;
            }
            return f.providerResponse(r);
          };
          await f.mount(t);
          if (flow.$3) {
            await f.quick(t);
          } else {
            await f.watch(t);
          }
          await f.until(t, () => waiting != null);
          if (flow.$2 == 'P2') {
            expect(
              find.textContaining('playing anything available'),
              findsOneWidget,
              reason:
                  'P2 reaches the quality fallback before Reset clears filters',
            );
          }

          await resetChannels(t, f);
          held.complete(await f.providerResponse(waiting!));
          await f.until(t, () => f.observer.players.isNotEmpty);
          final p = f.observer.players.single;
          final channel = !flow.$3 || flow.$2 == 'P3' || flow.$2 == 'P11';
          final values = debrifyTvPlayerFields(p);
          for (final field in [
            'startFromRandom',
            'hideSeekbar',
            'showChannelName',
            'showVideoTitle',
          ]) {
            expect(
              values[field],
              channel,
              reason:
                  '${flow.$2} uses ${channel ? 'channel' : 'quick'} $field after reset',
            );
          }
          expect(
            p.randomStartMaxPercent,
            channel ? 20 : 23,
            reason: '${flow.$2} uses distinct random percent',
          );
          expect(
            p.hideOptions,
            isFalse,
            reason: '${flow.$2} preserves hardcoded hideOptions',
          );
        });
      },
    );
  }

  for (final provider in ['real_debrid', 'alldebrid']) {
    testWidgets('0b O $provider invokes captured by-id callback', (t) async {
      await debrifyTvCase(t, (f) async {
        f.count = 3;
        await t.runAsync(() async {
          await f.provider(provider);
          await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
        });
        await f.mount(t);
        await f.watch(t);
        await f.until(t, () => f.observer.players.isNotEmpty);
        Map<String, dynamic>? value;
        var done = false;
        final pending = f
            .observer
            .players
            .single
            .requestChannelById!('original-2')
            .then((v) {
              value = v;
              done = true;
            });
        await f.until(t, () => done);
        await pending;
        expect(value, switched(2), reason: 'by-id selects original-2 exactly');
      });
    });
  }

  testWidgets('0b O switch finishes at five seconds plus one frame', (t) async {
    await debrifyTvCase(t, (f) async {
      f.count = 3;
      await t.runAsync(() async {
        await f.provider('alldebrid');
        await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
      });
      await f.mount(t);
      await f.watch(t);
      await f.until(t, () => f.observer.players.isNotEmpty);
      final previousDebugPrint = debugPrint;
      DateTime? cooldown;
      debugPrint = (message, {wrapWidth}) {
        if (message?.contains('Waiting for RD cooldown') ?? false) {
          cooldown = t.binding.clock.now();
        }
        previousDebugPrint(message, wrapWidth: wrapWidth);
      };
      try {
        var done = false;
        Map<String, dynamic>? value;
        final pending = f.observer.players.single.requestNextChannel!().then((
          v,
        ) {
          value = v;
          done = true;
        });
        await f.until(t, () => cooldown != null);
        final elapsed = t.binding.clock.now().difference(cooldown!);
        await t.pump(const Duration(milliseconds: 4999) - elapsed);
        expect(done, isFalse, reason: 'cooldown has a five-second lower bound');
        await t.pump(const Duration(milliseconds: 1));
        // Flush real storage/HTTP futures without advancing the fake clock.
        for (var i = 0; i < 400 && !done; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await t.pump();
        }
        await t.pump(const Duration(milliseconds: 16));
        expect(
          done,
          isTrue,
          reason: 'cooldown completes at five seconds plus one frame',
        );
        await pending;
        expect(
          value,
          switched(2),
          reason: 'next moves forward among three channels',
        );
      } finally {
        debugPrint = previousDebugPrint;
      }
    });
  });

  testWidgets(
    '0b O P1 gates next callback with independently changed Premiumize provider',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        await t.runAsync(() => f.provider('premiumize'));
        await t.runAsync(
          () => DebrifyTvStorage.saveDebrifyTvProvider('real_debrid'),
        );
        final held = Completer<http.Response>();
        http.Request? waiting;
        f.onRequest = (r) async {
          if (waiting == null) {
            waiting = r;
            return held.future;
          }
          return f.providerResponse(r);
        };
        await f.mount(t);
        await f.quick(t);
        await f.until(t, () => waiting != null);
        await t.runAsync(() async {
          await RealDebridStorage.setRealDebridIntegrationEnabled(false);
          await DebrifyTvCacheService.removeEntry('original-2');
        });
        // The public home handoff synchronizes provider availability even while
        // a quick search is held; the second channel has no pool and cannot push.
        MainPageBridge.watchDebrifyTvChannel!('original-2');
        await f.settle(t, frames: 20);
        held.complete(await f.providerResponse(waiting!));
        await f.until(t, () => f.observer.players.isNotEmpty);
        expect(
          f.observer.players.single.requestNextChannel,
          isNotNull,
          reason: 'P1 updated Premiumize provider still permits next',
        );
      });
    },
  );

  testWidgets('0b O library signal invalidates the cached pool before tuning', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      await f.mount(t);
      f.spotlight.view.onChannelFocused(f.channels.first);
      await f.until(t, () => f.spotlight.view.stats != null);
      final entry = await t.runAsync(
        () => DebrifyTvCacheService.getEntry('original-1'),
      );
      await t.runAsync(
        () => DebrifyTvCacheService.saveEntry(
          DebrifyTvChannelCacheEntry(
            version: entry!.version,
            channelId: entry.channelId,
            normalizedKeywords: entry.normalizedKeywords,
            fetchedAt: entry.fetchedAt,
            status: DebrifyTvCacheStatus.ready,
            errorMessage: null,
            torrents: const [],
            keywordStats: const {},
          ),
        ),
      );
      MainPageBridge.notifyDebrifyTvLibraryChanged();
      await f.settle(t, frames: 30);
      await f.watch(t);
      await f.settle(t, frames: 30);
      expect(
        f.observer.players,
        isEmpty,
        reason: 'signal evicts old cached playable torrent',
      );
    });
  });

  testWidgets(
    '0b R search Back reparks focus from the disappearing clear control',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.television = true;
        await f.mount(t);
        f.node('DebrifyTVChannelSearchButton').requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await f.settle(t);
        await t.enterText(find.byType(EditableText).last, 'original');
        await f.settle(t);
        f.node('DebrifyTVChannelSearchClear').requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        FocusManager.instance.applyFocusChangesIfNeeded();
        expect(
          f.node('DebrifyTVChannelSearch').hasFocus,
          isTrue,
          reason: 'Back reparks focus before the clear control is unmounted',
        );

        await t.pump();
        expect(
          f.node('DebrifyTVChannelSearch').hasFocus,
          isTrue,
          reason: 'Back reparks on search field after clearing',
        );
        expect(find.byType(EditableText), findsOneWidget);
      });
    },
  );

  testWidgets('0b O colliding imported name begins at suffix two', (t) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      await f.mount(t);
      final bytes = Uint8List.fromList(
        utf8.encode(importedYaml('Original channel 1')),
      );
      f.picker.next = FilePickerResult([
        PlatformFile(
          name: 'Original channel 1.yaml',
          size: bytes.length,
          bytes: bytes,
        ),
      ]);
      await chooseImport(t, f, 'From storage');
      await f.until(t, () => f.spotlight.view.channels.length == 3);
      final rows = await t.runAsync(
        DebrifyTvRepository.instance.fetchAllChannels,
      );
      expect(
        rows!.map((r) => r.name),
        contains('Original channel 1 (2)'),
        reason: 'first unique suffix is two',
      );
    });
  });

  testWidgets('0b O P12 stops an active prefetch after intercepted push', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.television = true;
      await t.runAsync(() async {
        await f.provider('alldebrid');
        await SettingsManager().setGlobalBackgroundPrefetchEnabled(true);
        await ExternalPlayerStorage.setDefaultPlayerMode('external');
        await ExternalPlayerStorage.setPreferredExternalPlayer('custom_app');
        await ExternalPlayerStorage.setCustomExternalPlayerPath(null);
      });
      final initial = Completer<http.Response>();
      final prefetch = Completer<http.Response>();
      http.Request? initialRequest;
      http.Request? prefetchRequest;
      var uploads = 0;
      var searches = 0;
      f.onRequest = (r) async {
        if (r.url.host == 'debrify-tv-original.test') {
          return f.jsonResponse({
            'results': [
              {
                'name': 'Original.720p.mkv',
                'infohash': String.fromCharCode(97 + searches++) * 40,
                'size': 100000000,
                'seeders': 20,
                'leechers': 1,
              },
            ],
          });
        }
        if (r.url.path.endsWith('/magnet/upload') && ++uploads == 2) {
          prefetchRequest = r;
          return prefetch.future;
        }
        if (r.url.path.endsWith('/link/unlock') && initialRequest == null) {
          initialRequest = r;
          return initial.future;
        }
        return f.providerResponse(r);
      };
      final previousDebugPrint = debugPrint;
      final events = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message?.trim() == 'MagicTV: Prefetch started.') {
          events.add('prefetch start');
        }
        if (message?.trim() == 'MagicTV: Prefetch stopped.') {
          events.add('prefetch stop');
        }
        previousDebugPrint(message, wrapWidth: wrapWidth);
      };
      f.observer.onEvent = events.add;
      try {
        await f.mount(t);
        expect(
          await t.runAsync(ExternalPlayerStorage.getDefaultPlayerMode),
          'external',
        );
        await f.quick(t, keywords: 'one,two,three');
        await f.until(t, () => initialRequest != null);
        expect(find.text('Cancel'), findsOneWidget);
        initial.complete(await f.providerResponse(initialRequest!));
        await f.until(
          t,
          () => find.text('Opening another player').evaluate().isNotEmpty,
        );
        await f.until(t, () => prefetchRequest != null);
        expect(
          events,
          contains('prefetch start'),
          reason: 'active prefetch before external notice',
        );
        events.add('handoff');
        await f.tap(t, find.text('Continue'));
        await f.until(t, () => f.observer.players.isNotEmpty);
        prefetch.complete(await f.providerResponse(prefetchRequest!));
        await f.settle(t, frames: 40);
        expect(
          uploads,
          2,
          reason: 'P12 stops before acquiring a third torrent',
        );
        expect(
          events,
          contains('prefetch stop'),
          reason: 'P12 stops active prefetch after push',
        );
        expect(
          events,
          containsAllInOrder([
            'dialog close',
            'prefetch start',
            'handoff',
            'push',
            'prefetch stop',
          ]),
          reason: 'P12 active prefetch stops after push exit',
        );
      } finally {
        debugPrint = previousDebugPrint;
      }
    });
  });

  testWidgets('0b O next callback uses the channel selected by id', (t) async {
    await debrifyTvCase(t, (f) async {
      f.count = 3;
      await t.runAsync(() async {
        await f.provider('alldebrid');
        await SettingsManager().setGlobalBackgroundPrefetchEnabled(false);
      });
      await f.mount(t);
      await f.watch(t);
      await f.until(t, () => f.observer.players.isNotEmpty);
      final player = f.observer.players.single;
      var done = false;
      Map<String, dynamic>? direct;
      final first = player.requestChannelById!('original-2').then((v) {
        direct = v;
        done = true;
      });
      await f.until(t, () => done);
      await first;
      expect(direct, switched(2));
      done = false;
      Map<String, dynamic>? next;
      final pending = player.requestNextChannel!().then((v) {
        next = v;
        done = true;
      });
      await f.until(t, () => done);
      await pending;
      expect(
        next,
        switched(3),
        reason: 'next starts from the current channel selected by id',
      );
    });
  });

  testWidgets('0b O TorBox queued Cancel after handoff suppresses final push', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.television = true;
      await t.runAsync(() async {
        await f.provider('torbox');
        await ExternalPlayerStorage.setDefaultPlayerMode('external');
        await ExternalPlayerStorage.setPreferredExternalPlayer('custom_app');
        await ExternalPlayerStorage.setCustomExternalPlayerPath(null);
      });
      final held = Completer<http.Response>();
      http.Request? waiting;
      f.onRequest = (r) async {
        if (r.url.path.endsWith('/requestdl') && waiting == null) {
          waiting = r;
          return held.future;
        }
        return f.providerResponse(r);
      };
      await f.mount(t);
      await f.quick(t);
      await f.until(t, () => waiting != null);
      final cancel = t
          .widget<CachedLoadingDialog>(find.byType(CachedLoadingDialog))
          .onCancel!;
      held.complete(await f.providerResponse(waiting!));
      await f.until(
        t,
        () => find.text('Opening another player').evaluate().isNotEmpty,
      );
      await f.settle(t, frames: 15);
      // Dispatch the captured ORIGINAL cancel action after the progress route
      // has left. The original catch handles its stale dialog context; the
      // external notice remains the async boundary before the native attempt.
      cancel();
      await t.pump();
      expect(find.text('Opening another player'), findsOneWidget);
      await f.tap(t, find.text('Continue'));
      await f.settle(t, frames: 50);
      expect(
        f.observer.players,
        isEmpty,
        reason: 'final TorBox guards honour queued Cancel before push',
      );
      final requests = f.requests.length;
      await f.settle(t, frames: 30);
      expect(
        f.requests.length,
        requests,
        reason: 'no further TorBox requests after queued Cancel',
      );
    });
  });

  testWidgets('0b O P5 closes progress before prefetch and external notice', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.television = true;
      f.cacheKeywords = const [
        ['one'],
        ['two'],
        ['three'],
      ];
      await t.runAsync(() async {
        await ExternalPlayerStorage.setDefaultPlayerMode('external');
        await ExternalPlayerStorage.setPreferredExternalPlayer('custom_app');
        await ExternalPlayerStorage.setCustomExternalPlayerPath(null);
      });
      final events = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message == 'MagicTV: Prefetch started.') {
          events.add('prefetch start');
        }
        previousDebugPrint(message, wrapWidth: wrapWidth);
      };
      f.observer.onEvent = events.add;
      try {
        await f.mount(t);
        await f.watch(t);
        await f.until(
          t,
          () => find.text('Opening another player').evaluate().isNotEmpty,
        );
        expect(
          events,
          containsAllInOrder(['dialog close', 'prefetch start', 'dialog']),
          reason:
              'P5 closes progress before prefetch starts and the external notice',
        );
        await f.tap(t, find.text('Cancel'));
        expect(f.observer.players, isEmpty);
      } finally {
        debugPrint = previousDebugPrint;
      }
    });
  });

  for (final site in ['P2', 'P5']) {
    testWidgets('0b O $site queued Cancel invalidates a pending prefetch start', (
      t,
    ) async {
      await debrifyTvCase(t, (f) async {
        f.cacheKeywords = const [
          ['one'],
          ['two'],
          ['three'],
        ];
        await t.runAsync(() async {
          await SettingsManager().setGlobalBackgroundPrefetchEnabled(true);
          if (site == 'P2') {
            await DebrifyTvStorage.setDebrifyTvFilterQualities(['ultraHd']);
          }
        });
        final held = Completer<http.Response>();
        http.Request? waiting;
        f.onRequest = (r) async {
          if (r.url.path.endsWith('/unrestrict/link') && waiting == null) {
            waiting = r;
            return held.future;
          }
          return f.providerResponse(r);
        };
        await f.mount(t);
        if (site == 'P2') {
          await f.quick(t);
        } else {
          await f.watch(t);
        }
        await f.until(t, () => waiting != null);
        final cancel = t
            .widget<CachedLoadingDialog>(find.byType(CachedLoadingDialog))
            .onCancel!;
        var cancelled = false;
        f.observer.onEvent = (event) {
          if (event == 'dialog close' && !cancelled) {
            cancelled = true;
            cancel();
          }
        };
        held.complete(await f.providerResponse(waiting!));
        await f.until(t, () => f.observer.players.isNotEmpty);
        expect(cancelled, isTrue);
        await f.settle(t, frames: 30);
        expect(
          f.debugMessages.where((m) => m == 'MagicTV: Prefetch started.'),
          isEmpty,
          reason:
              '$site Cancel invalidates the async prefetch start at progress close',
        );
        expect(
          f.rdAdds,
          1,
          reason: '$site cancelled queue issues no further provider adds',
        );
      });
    });
  }
}
