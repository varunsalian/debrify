import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_settings_two_pane_fixture.dart';

void main() {
  for (final count in [0, 1, 3]) {
    for (final appearance in [false, true]) {
      for (final recording in [false, true]) {
        testWidgets(
          'rail order indices and neighbours sources=$count appearance=$appearance recording=$recording',
          (t) async {
            await twoPaneCase(t, (f) async {
              f.playlists = List.generate(count, (i) => twoPaneSource('$i'));
              f.appearance = appearance;
              f.recording = recording;
              await f.mount(t);
              final names = [
                for (var i = 0; i < count; i++) 'Source $i',
                'Add a source',
                'Channel lists',
                'Startup channel',
                'Channel preview',
                'Continue watching',
                if (appearance) 'Appearance',
                'Player guide',
                if (recording) 'Recording',
                'Auto-refresh',
              ];
              final keys = [
                for (var i = 0; i < count; i++) 'source:$i',
                'add',
                'lists',
                'startup',
                'channel-preview',
                'continue-watching',
                if (appearance) 'appearance',
                'player_guide',
                if (recording) 'recording',
                'auto-refresh',
              ];
              expect(
                f.rails(t).map((e) => e.title),
                names,
                reason: 'complete rail order',
              );
              await f.focusIndex(t, 0);
              for (var i = 0; i < names.length; i++) {
                expect(
                  FocusManager.instance.primaryFocus?.debugLabel,
                  'iptv-2p-rail-$i',
                  reason: 'rail DOWN neighbour $i',
                );
                expect(
                  f.paneKey,
                  keys[i],
                  reason: 'rail preview destination $i',
                );
                if (i < names.length - 1) {
                  await f.keyEvent(t, LogicalKeyboardKey.arrowDown);
                }
              }
              f.escapedKeys.clear();
              await f.keyEvent(t, LogicalKeyboardKey.arrowDown);
              expect(f.escapedKeys, isEmpty, reason: 'bottom DOWN consumed');
              expect(
                FocusManager.instance.primaryFocus?.debugLabel,
                'iptv-2p-rail-${names.length - 1}',
              );
              for (var i = names.length - 2; i >= 0; i--) {
                await f.keyEvent(t, LogicalKeyboardKey.arrowUp);
                expect(
                  FocusManager.instance.primaryFocus?.debugLabel,
                  'iptv-2p-rail-$i',
                  reason: 'rail UP neighbour $i',
                );
              }
              f.escapedKeys.clear();
              await f.keyEvent(t, LogicalKeyboardKey.arrowUp);
              expect(f.escapedKeys, [
                LogicalKeyboardKey.arrowUp,
              ], reason: 'top UP escapes to host');
              f.escapedKeys.clear();
              await f.keyEvent(t, LogicalKeyboardKey.arrowLeft);
              expect(f.escapedKeys, [
                LogicalKeyboardKey.arrowLeft,
              ], reason: 'rail LEFT ignored');
            });
          },
        );
      }
    }
  }
  testWidgets(
    'initial destination default fallback openAdd and deleted-source rehome',
    (t) async {
      await twoPaneCase(t, (f) async {
        await f.mount(t);
        expect(
          f.paneKey,
          'source:b',
          reason: 'default source selected at opening',
        );
        f.playlists = [twoPaneSource('a')];
        await f.refresh(t);
        expect(f.paneKey, 'source:a', reason: 'deleted source rehomed');
        f.playlists = [];
        await f.refresh(t);
        expect(f.paneKey, 'add', reason: 'last source removed rehomes to Add');
        expect(t.takeException(), isNull);
      });
      await twoPaneCase(t, (f) async {
        f.defaultId = 'absent';
        await f.mount(t);
        expect(
          f.paneKey,
          'source:a',
          reason: 'unknown default falls back to first source',
        );
      });
      await twoPaneCase(t, (f) async {
        f.openAddSource = true;
        await f.mount(t);
        expect(f.paneKey, 'add', reason: 'openAddSource overrides default');
        f.openAddSource = false;
        await f.refresh(t);
        expect(f.paneKey, 'add', reason: 'openAddSource is opening-only');
      });
    },
  );
  testWidgets(
    'grow-only surplus rail nodes retain identity through shrink and regrow',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.appearance = false;
        f.recording = false;
        await f.mount(t);
        final old = f.rails(t).map((e) => e.focusNode as FocusNode).toList();
        expect(old.length, 10);
        f.playlists = [twoPaneSource('a')];
        await f.refresh(t);
        expect(f.rails(t).length, 8);
        expect(old[8].context?.mounted ?? false, isFalse);
        expect(old[9].context?.mounted ?? false, isFalse);
        f.playlists = [
          twoPaneSource('a'),
          twoPaneSource('b'),
          twoPaneSource('c'),
        ];
        await f.refresh(t);
        final grown = f.rails(t);
        for (final index in [8, 9]) {
          expect(
            identical(grown[index].focusNode, old[index]),
            isTrue,
            reason: 'surplus node $index reused after regrow',
          );
          await f.focusIndex(t, index);
          expect(
            old[index].context?.mounted,
            isTrue,
            reason: 'same surplus node attached again',
          );
        }
        expect(t.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'stale source callback cannot focus a spare beyond rendered rail count',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.playlists = List.generate(12, (i) => twoPaneSource('$i'));
        await f.mount(t);
        final VoidCallback staleDown = f.rails(t)[11].onDown as VoidCallback;
        f.playlists = [twoPaneSource('0')];
        await f.refresh(t);
        await f.focusIndex(t, 0);
        staleDown();
        await f.frame(t);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-rail-0',
          reason: 'spare cannot swallow focus',
        );
        f.playlists = List.generate(12, (i) => twoPaneSource('$i'));
        await f.refresh(t);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-rail-0',
          reason: 'ignored spare request stays ignored when node reattaches',
        );
      });
    },
  );
  for (final key in [
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.space,
  ]) {
    testWidgets('rail $key enters pane and LEFT returns to selected source', (
      t,
    ) async {
      await twoPaneCase(t, (f) async {
        await f.mount(t);
        await f.focusIndex(t, 2);
        await f.keyEvent(t, key);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-pane-0',
          reason: 'rail enters first source action',
        );
        await f.keyEvent(t, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-rail-2',
          reason: 'LEFT returns to owning source',
        );
        await f.keyEvent(t, key);
        f.key.currentState!.focusRail();
        await f.frame(t);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-rail-2',
          reason: 'public focusRail follows selection',
        );
      });
    });
  }
  testWidgets('rail repeat advances twice and centres focused entry', (
    t,
  ) async {
    await twoPaneCase(t, (f) async {
      await f.mount(t);
      await f.focusIndex(t, 0);
      await f.repeat(t, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-2p-rail-2',
        reason: 'KeyRepeat rail neighbour',
      );
      await f.destination(t, 'Auto-refresh');
      final rect = t.getRect(f.railEntries.last);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(800));
    });
  });
  testWidgets('rail mouse hover does nothing and pointer click only focuses', (
    t,
  ) async {
    await twoPaneCase(t, (f) async {
      await f.mount(t);
      final rail = f.railEntries.at(2);
      await f.mouse(t, t.getCenter(rail));
      expect(f.paneKey, 'source:b', reason: 'hover never previews');
      await f.mouse(t, t.getCenter(rail), click: true);
      expect(f.paneKey, 'source:c', reason: 'click previews source');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-2p-rail-2',
        reason: 'rail pointer never enters pane',
      );
      expect(f.events, isEmpty);
    });
  });
  for (final method in [0, 1, 2, 99]) {
    testWidgets('Add entry picks method $method and host owns method nodes', (
      t,
    ) async {
      await twoPaneCase(t, (f) async {
        f.addMethod = method;
        await f.mount(t);
        await f.destination(t, 'Add a source');
        await f.keyEvent(t, LogicalKeyboardKey.arrowRight);
        expect(
          f
              .methods[method == 1
                  ? 1
                  : method == 2
                  ? 2
                  : 0]
              .hasPrimaryFocus,
          isTrue,
          reason: 'selected Add method node',
        );
        await f.keyEvent(t, LogicalKeyboardKey.arrowDown);
        expect(f.events, ['form-focus']);
        await t.pumpWidget(const SizedBox.shrink());
        for (final node in f.methods) {
          expect(
            () => node.addListener(() {}),
            returnsNormally,
            reason: 'host node not disposed by view',
          );
        }
      });
    });
  }
  testWidgets(
    'focusAddPane already Add requests once in same frame on attached node',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.openAddSource = true;
        f.addMethod = 1;
        await f.mount(t);
        f.clearRequests();
        final frame = f.frameNumber;
        f.key.currentState!.focusAddPane();
        expect(f.file.requests, [
          (frame: frame, attached: true),
        ], reason: 'already Add immediate single request');
        await f.frame(t);
        expect(f.file.requests.length, 1);
        expect(f.file.hasPrimaryFocus, isTrue);
      });
    },
  );
  testWidgets(
    'focusAddPane switches then requests once after frame on attached node',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.addMethod = 2;
        await f.mount(t);
        f.clearRequests();
        final before = f.frameNumber;
        f.key.currentState!.focusAddPane();
        expect(
          f.xtream.requests,
          isEmpty,
          reason: 'no request before Add switch frame',
        );
        await f.frame(t);
        expect(
          f.xtream.requests.length,
          1,
          reason: 'single post-frame request',
        );
        expect(
          f.xtream.requests.single.attached,
          isTrue,
          reason: 'request after method attachment',
        );
        expect(f.xtream.requests.single.frame, greaterThan(before));
        expect(f.xtream.hasPrimaryFocus, isTrue);
      });
    },
  );
  testWidgets('focusAddPane unmount before post-frame requests nothing', (
    t,
  ) async {
    await twoPaneCase(t, (f) async {
      await f.mount(t);
      f.clearRequests();
      f.key.currentState!.focusAddPane();
      await t.pumpWidget(const SizedBox.shrink());
      expect(
        [f.url.requests, f.file.requests, f.xtream.requests],
        everyElement(isEmpty),
        reason: 'mounted guard rejects unmounted request',
      );
      expect(t.takeException(), isNull);
    });
  });
}
