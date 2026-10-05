import 'package:debrify/features/home/presentation/home_hero_shell_bridge.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/screens/debrify_tv/widgets/random_start_slider.dart';
import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/debrify_tv_fixture.dart';

Future<Map<String, Object?>> prefs() async {
  final store = await ProfilePreferences.instance();
  return {
    for (final key in store.getKeys().where((k) => k.startsWith('debrify_tv')))
      key: store.get(key),
  };
}

void main() {
  for (final pending in [true, false]) {
    testWidgets(
      'C2 O shell ${pending ? 'pending' : 'mounted'} play starts saved channel unknown id does nothing',
      (t) async {
        await debrifyTvCase(t, (f) async {
          if (pending) {
            HomeHeroShellBridge.playSavedDebrifyChannel('original-1');
            expect(f.observer.players, isEmpty);
          }
          await f.mount(t);
          if (!pending) {
            HomeHeroShellBridge.playSavedDebrifyChannel('original-1');
          }
          await f.until(t, () => f.observer.players.isNotEmpty);
          expect(f.observer.players.single.channelName, 'Original channel 1');
          HomeHeroShellBridge.playSavedDebrifyChannel('unknown');
          await f.settle(t, frames: 20);
          expect(f.observer.players, hasLength(1));
        });
      },
    );
  }

  testWidgets(
    'C2 C8 R library signal reloads rows and invalidates stage stats',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        await f.mount(t);
        f.spotlight.view.onChannelFocused(f.channels.first);
        await f.until(t, () => f.spotlight.view.stats != null);
        expect(f.spotlight.view.stats!.pooled, 1);
        await t.runAsync(() async {
          await DebrifyTvRepository.instance.upsertChannel(
            DebrifyTvChannelRecord(
              channelId: 'signal-3',
              name: 'Signal third',
              keywords: const ['signal'],
              avoidNsfw: true,
              channelNumber: 3,
              createdAt: f.january,
              updatedAt: f.january,
            ),
          );
          await DebrifyTvCacheService.clearAll();
        });
        MainPageBridge.notifyDebrifyTvLibraryChanged();
        await f.until(t, () => f.spotlight.view.channels.length == 3);
        expect(find.text('Signal third'), findsWidgets);
        expect(
          f.spotlight.view.stats,
          isNull,
          reason: 'library signal clears stage stats',
        );
      });
    },
  );

  testWidgets(
    'C4 C10 R/O live setters render and persist their own stored values',
    (t) async {
      await debrifyTvCase(t, (f) async {
        await t.runAsync(() async {
          await DebrifyTvStorage.saveDebrifyTvStartRandom(true);
          await DebrifyTvStorage.saveDebrifyTvRandomStartPercent(65);
          await DebrifyTvStorage.saveDebrifyTvHideSeekbar(true);
          await DebrifyTvStorage.saveDebrifyTvShowChannelName(true);
          await DebrifyTvStorage.saveDebrifyTvShowVideoTitle(true);
        });
        await f.mount(t);
        await f.settings(t);
        expect(find.text('Real Debrid'), findsWidgets);
        expect(
          t.widget<SwitchRow>(find.byType(SwitchRow).first).value,
          isTrue,
          reason: '_loadSettings publishes stored startRandom',
        );
        expect(
          t.widget<RandomStartSlider>(find.byType(RandomStartSlider)).value,
          65,
        );
        final slider = t.widget<RandomStartSlider>(
          find.byType(RandomStartSlider),
        );
        slider.onChanged(70);
        slider.onChangeEnd!(70);
        await f.settle(t);
        expect(
          t.widget<RandomStartSlider>(find.byType(RandomStartSlider)).value,
          70,
        );
        expect(
          await t.runAsync(DebrifyTvStorage.getDebrifyTvRandomStartPercent),
          70,
        );
        t.widget<SwitchRow>(find.byType(SwitchRow).first).onChanged(false);
        await f.settle(t);
        expect(find.byType(RandomStartSlider), findsNothing);
        expect(
          await t.runAsync(DebrifyTvStorage.getDebrifyTvStartRandom),
          isFalse,
        );
        expect(
          f.originalLayoutDiagnostics,
          isNotEmpty,
          reason:
              'R reports the existing SwitchRow ListTile decoration diagnostic',
        );
        await f.tap(t, find.text('Done'));
        await f.watch(t);
        await f.until(t, () => f.observer.players.isNotEmpty);
        final p = f.observer.players.single;
        expect(p.randomStartMaxPercent, 70);
        expect(p.showChannelName, isTrue);
        expect(p.showVideoTitle, isTrue);
        expect(
          p.hideSeekbar,
          isFalse,
          reason:
              'ORIGINAL _loadSettings rewrites hideSeekbar from hardcoded hideOptions',
        );
        expect(p.hideOptions, isFalse);
      });
    },
  );

  testWidgets('C4 O quick options copied to P12 without preference writes', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      await t.runAsync(() => f.provider('alldebrid'));
      await t.runAsync(() async {
        await DebrifyTvStorage.saveDebrifyTvStartRandom(true);
        await DebrifyTvStorage.saveDebrifyTvRandomStartPercent(55);
        await DebrifyTvStorage.saveDebrifyTvShowChannelName(true);
        await DebrifyTvStorage.saveDebrifyTvShowVideoTitle(true);
      });
      await f.mount(t);
      final before = await t.runAsync(prefs);
      await f.quick(t);
      await f.until(t, () => f.observer.players.isNotEmpty);
      final p = f.observer.players.single;
      expect(p.startFromRandom, isTrue);
      expect(p.randomStartMaxPercent, 55);
      expect(p.showChannelName, isTrue);
      expect(p.showVideoTitle, isTrue);
      expect(
        await t.runAsync(prefs),
        before,
        reason: 'Play now copies quick fields without persisting them',
      );
    });
  });

  testWidgets('C4 O Reset writes exactly original key set', (t) async {
    await debrifyTvCase(t, (f) async {
      await f.mount(t);
      await f.settings(t);
      final before = await t.runAsync(prefs);
      await f.tap(t, find.text('Reset to defaults'));
      final after = await t.runAsync(prefs);
      final changed = after!.keys.where((k) => before![k] != after[k]).toSet();
      expect(changed, {
        'debrify_tv_start_random',
        'debrify_tv_hide_seekbar',
        'debrify_tv_show_watermark',
        'debrify_tv_show_video_title',
        'debrify_tv_filter_qualities',
        'debrify_tv_filter_sizes',
      });
      expect(
        after['debrify_tv_random_start_percent'],
        23,
        reason: 'ORIGINAL Reset does not persist random percent',
      );
      expect(after.keys.toSet().difference(before!.keys.toSet()), {
        'debrify_tv_filter_qualities',
        'debrify_tv_filter_sizes',
      });
      expect(find.text('Reset to defaults successful'), findsOneWidget);
    });
  });

  testWidgets('C4 C10 R availability sync enables TorBox after adding key', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      await f.mount(t);
      await f.settings(t);
      // The disabled chip retains its rendered unavailable caption.
      expect(
        t
            .widget<GestureDetector>(
              find
                  .ancestor(
                    of: find.text('Torbox'),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .onTap,
        isNull,
      );
      await f.tap(t, find.text('Done'));
      await t.runAsync(() async {
        await TorboxStorage.saveTorboxApiKey('new-original-key');
        await TorboxStorage.setTorboxIntegrationEnabled(true);
      });
      f.spotlight.view
          .onAdd(); // existing action owns _syncProviderAvailability
      await f.until(t, () => find.text('Save channel').evaluate().isNotEmpty);
      await f.tap(t, find.text('Cancel'));
      await f.settings(t);
      expect(find.text('Torbox'), findsOneWidget);
      expect(
        t
            .widget<GestureDetector>(
              find
                  .ancestor(
                    of: find.text('Torbox'),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .onTap,
        isNotNull,
      );
    });
  });

  testWidgets(
    'C4 R child NSFW editor and quick switches stay forced and inert',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        f.childProfile = true;
        await f.mount(t);
        f.spotlight.view.onEdit(f.channels.first);
        await f.until(t, () => find.text('Save channel').evaluate().isNotEmpty);
        expect(find.text('Always on for this profile'), findsOneWidget);
        t.widget<SwitchRow>(find.byType(SwitchRow)).onChanged(false);
        await f.settle(t);
        expect(
          t.widget<SwitchRow>(find.byType(SwitchRow)).value,
          isTrue,
          reason: 'child NSFW remains forced in editor',
        );
        await f.tap(t, find.text('Cancel'));
        f.spotlight.view.onQuickPlay();
        await f.settle(t);
        t.widget<SwitchRow>(find.byType(SwitchRow)).onChanged(false);
        await f.settle(t);
        expect(
          t.widget<SwitchRow>(find.byType(SwitchRow)).value,
          isTrue,
          reason: 'child NSFW remains forced in quick dialog',
        );
      });
    },
  );

  testWidgets(
    'C5 R/O favorites first persisted toggle delete cancel and delete all',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        f.goldenFavorites = true;
        await f.mount(t);
        expect(f.spotlight.view.favoriteIds, {'original-2'});
        final first = t.getTopLeft(find.text('Original channel 2').first);
        final second = t.getTopLeft(find.text('Original channel 1').first);
        expect(
          first.dy,
          lessThan(second.dy),
          reason: 'favorites precede unpinned rows',
        );
        f.spotlight.view.onToggleFavorite(f.channels.first);
        await f.settle(t);
        expect(
          await t.runAsync(
            () => DebrifyTvStorage.isDebrifyTvChannelFavorited('original-1'),
          ),
          isTrue,
        );
        f.spotlight.view.onDelete(f.channels.first);
        await f.settle(t);
        expect(find.text('Delete Original channel 1?'), findsOneWidget);
        await f.tap(t, find.text('Cancel'));
        expect(
          (await t.runAsync(
            DebrifyTvRepository.instance.fetchAllChannels,
          ))!.length,
          2,
        );
        f.spotlight.view.onDelete(f.channels.first);
        await f.settle(t);
        await f.tap(t, find.text('Delete channel'));
        await f.until(t, () => f.spotlight.view.channels.length == 1);
        expect(
          (await t.runAsync(
            DebrifyTvRepository.instance.fetchAllChannels,
          ))!.single.channelId,
          'original-2',
        );
        f.spotlight.view.onDeleteAll();
        await f.settle(t);
        await f.tap(t, find.text('Cancel'));
        expect(f.spotlight.view.channels, hasLength(1));
        f.spotlight.view.onDeleteAll();
        await f.settle(t);
        await f.tap(t, find.text('Delete all'));
        await f.until(t, () => f.spotlight.view.channels.isEmpty);
        expect(
          await t.runAsync(DebrifyTvRepository.instance.fetchAllChannels),
          isEmpty,
        );
        expect(
          await t.runAsync(() => DebrifyTvCacheService.getEntry('original-2')),
          isNull,
        );
      });
    },
  );

  testWidgets(
    'C8 R Spotlight debounce and memo return cancel pending B timer',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        f.television = true;
        await f.mount(t);
        expect(MainPageBridge.requestTvContentFocus(), isTrue);
        await t.pump();
        expect(f.node('DebrifyTVQuickPlay').hasFocus, isTrue);
        f.spotlight.view.onChannelFocused(f.channels.first);
        await t.pump(const Duration(milliseconds: 249));
        expect(f.spotlight.view.stats, isNull);
        await t.pump(const Duration(milliseconds: 1));
        await f.until(t, () => f.spotlight.view.stats != null);
        final memo = f.spotlight.view.stats;
        f.spotlight.view.onChannelFocused(f.channels[1]);
        await t.pump(const Duration(milliseconds: 100));
        expect(f.spotlight.view.stats, isNull);
        f.spotlight.view.onChannelFocused(f.channels.first);
        await t.pump();
        expect(f.spotlight.view.stats, same(memo));
        await t.pump(const Duration(milliseconds: 251));
        expect(f.spotlight.view.stats, same(memo));
        f.spotlight.view.onChannelFocused(f.channels[1]);
        await t.pump();
        expect(
          f.spotlight.view.stats,
          isNull,
          reason: 'memo return cancels B timer; B was never memoized off focus',
        );
      });
    },
  );

  testWidgets(
    'C9 R/O top actions D-pad sidebar traversal Select search Escape ladder',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.television = true;
        await f.mount(t);
        f.node('DebrifyTVQuickPlay').requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        expect(f.probes, contains('sidebar'));
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        expect(f.node('DebrifyTVChannelSearchButton').hasFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await f.settle(t);
        expect(f.node('DebrifyTVChannelSearch').hasFocus, isTrue);
        await t.enterText(find.byType(EditableText), 'Original channel 1');
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(
          t.widget<EditableText>(find.byType(EditableText)).controller.text,
          isEmpty,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await f.settle(t);
        expect(find.byType(EditableText), findsNothing);
        expect(f.node('DebrifyTVChannelSearchButton').hasFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        expect(f.node('DebrifyTVChannelMenu').hasFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await f.settle(t);
        expect(find.text('Import'), findsWidgets);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await f.settle(t);
        expect(f.node('DebrifyTVChannelMenu').hasFocus, isTrue);
      });
    },
  );
}
