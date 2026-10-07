import 'package:debrify/services/iptv_media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_settings_two_pane_fixture.dart';

void expectCentred(WidgetTester t, Finder entry, String reason) {
  final target = t.renderObject(entry);
  final viewport = RenderAbstractViewport.of(target);
  final scrollable = Scrollable.of(t.element(entry));
  final expected = viewport
      .getOffsetToReveal(target, 0.5)
      .offset
      .clamp(
        scrollable.position.minScrollExtent,
        scrollable.position.maxScrollExtent,
      );
  expect(scrollable.position.pixels, closeTo(expected, 0.01), reason: reason);
  expect(
    scrollable.position.pixels,
    greaterThan(0),
    reason: 'scrolled far entry',
  );
}

void main() {
  for (final count in [0, 1, 3]) {
    for (final appearance in [false, true]) {
      for (final recording in [false, true]) {
        testWidgets(
          'pane preview headers and keys sources=$count appearance=$appearance recording=$recording',
          (t) async {
            await twoPaneCase(t, (f) async {
              // Retain real source focus callbacks. After the sources shrink,
              // their indices reach _destForRail's settings branches.
              f.playlists = List.generate(16, (i) => twoPaneSource('$i'));
              await f.mount(t);
              final callbacks = f
                  .rails(t)
                  .take(16)
                  .map((e) => e.onFocused as VoidCallback)
                  .toList();
              f.playlists = List.generate(count, (i) => twoPaneSource('$i'));
              f.appearance = appearance;
              f.recording = recording;
              await f.refresh(t);
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
              for (var i = 0; i < names.length; i++) {
                await f.focusIndex(t, i);
                expect(
                  (t.widget(f.pieces('PaneHeader')) as dynamic).title,
                  names[i],
                  reason: 'focused rail pane header $i',
                );
                expect(
                  find.byKey(ValueKey(keys[i])),
                  findsOneWidget,
                  reason: 'per-destination ListView key exists $i',
                );
                expect(
                  f.paneKey,
                  keys[i],
                  reason: 'focused rail ListView key $i',
                );
                callbacks[i]();
                await f.frame(t);
                expect(
                  (t.widget(f.pieces('PaneHeader')) as dynamic).title,
                  names[i],
                  reason: 'retained source callback pane header $i',
                );
                expect(
                  f.paneKey,
                  keys[i],
                  reason: 'retained source callback ListView key $i',
                );
              }
            });
          },
        );
      }
    }
  }
  for (final count in [0, 1, 2]) {
    testWidgets('hidden categories subtitle count=$count', (t) async {
      await twoPaneCase(t, (f) async {
        f.playlists = [twoPaneSource('a')];
        f.hiddenCounts = {'a': count};
        await f.mount(t);
        expect(
          (t.widget(f.row('Hidden categories')) as dynamic).subtitle,
          switch (count) {
            0 => 'Nothing hidden from this source',
            1 => '1 category hidden',
            _ => '2 categories hidden',
          },
          reason: 'hidden categories exact singular and plural',
        );
      });
    });
  }
  for (final kind in ['URL', 'Xtream', 'Local file']) {
    testWidgets('uncached source rail subtitle is exactly $kind', (t) async {
      await twoPaneCase(t, (f) async {
        f.playlists = [
          twoPaneSource(
            'a',
            xtream: kind == 'Xtream',
            local: kind == 'Local file',
          ),
        ];
        await f.mount(t);
        expect(
          f.rails(t).first.subtitle,
          kind,
          reason: 'uncached rail has kind without a fabricated channel count',
        );
      });
    });
  }
  testWidgets('rail far entry has centred scroll offset', (t) async {
    await twoPaneCase(t, (f) async {
      f.playlists = List.generate(24, (i) => twoPaneSource('$i'));
      await f.mount(t, size: const Size(1280, 480));
      await f.focusIndex(t, 12);
      final entry = find.byWidgetPredicate(
        (w) =>
            [
              '_RailEntry',
              'IptvTwoPaneRailEntry',
            ].contains(w.runtimeType.toString()) &&
            (w as dynamic).focusNode.debugLabel == 'iptv-2p-rail-12',
      );
      expectCentred(
        t,
        entry,
        'rail far entry is centred rather than top-aligned',
      );
    });
  });
  testWidgets('pane far row has centred scroll offset', (t) async {
    await twoPaneCase(t, (f) async {
      f.lists = List.generate(
        18,
        (i) => IptvListMeta(
          id: '$i',
          name: 'Saved list $i',
          position: i,
          isBuiltin: false,
          channelCount: 1,
        ),
      );
      await f.mount(t, size: const Size(1280, 480));
      await f.destination(t, 'Channel lists');
      final pane = find.byKey(const ValueKey('lists'));
      await t.drag(pane, const Offset(0, -720));
      await f.frame(t);
      final row = f.row('Saved list 10');
      final node = (t.widget(row) as dynamic).focusNode as FocusNode;
      expect(node.context, isNotNull, reason: 'far pane pool node attached');
      node.requestFocus();
      await f.frame(t);
      expectCentred(t, row, 'pane far row is centred rather than top-aligned');
    });
  });
}
