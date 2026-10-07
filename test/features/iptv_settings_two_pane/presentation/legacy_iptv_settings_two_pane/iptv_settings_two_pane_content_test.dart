import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_settings_two_pane_fixture.dart';

List<String> titles(WidgetTester t, IptvSettingsTwoPaneFixture f) => t
    .widgetList(f.paneRows)
    .map((w) => (w as dynamic).title as String)
    .toList();
void main() {
  for (final kind in ['url', 'xtream', 'local', 'shared', 'redacted']) {
    testWidgets('source $kind rows metadata badges and host action arguments', (
      t,
    ) async {
      await twoPaneCase(t, (f) async {
        final p = twoPaneSource(
          kind,
          xtream: kind == 'xtream',
          local: kind == 'local',
          shared: kind == 'shared' || kind == 'redacted',
          redacted: kind == 'redacted',
          epgUrl: 'https://fixture.invalid/guide.xml',
        );
        f.playlists = [p];
        f.defaultId = p.id;
        f.hiddenCounts = {p.id: 2};
        await f.mount(t);
        final readonly = kind == 'shared' || kind == 'redacted';
        expect(titles(t, f), [
          if (kind != 'local' && !readonly) 'Refresh now',
          'Default playlist',
          if (!readonly) 'Edit source',
          if (kind != 'local') 'Hidden categories',
          'Category order',
          if (!readonly) 'Guide (EPG) source',
          if (!readonly) 'Remove source',
        ], reason: 'source-specific action rows');
        expect(find.text('Default'), findsOneWidget);
        expect(find.text('Shared'), readonly ? findsOneWidget : findsNothing);
        expect(
          find.text('2 categories hidden'),
          kind == 'local' ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Custom XMLTV URL set for this source'),
          readonly ? findsNothing : findsOneWidget,
        );
        if (kind == 'redacted') {
          expect(
            find.text('Shared connection · credentials hidden'),
            findsOneWidget,
          );
          expect(find.textContaining('fixture-user'), findsNothing);
          expect(find.textContaining('original-password'), findsNothing);
        } else if (kind == 'xtream') {
          expect(
            find.text(
              'Xtream Codes · https://fixture.invalid/panel · fixture-user',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('original-password'), findsNothing);
        } else if (kind == 'local') {
          expect(
            find.text(
              'Imported from a file — it plays from the copy stored in the app.',
            ),
            findsOneWidget,
          );
        } else {
          expect(
            find.text('https://fixture.invalid/$kind.m3u'),
            findsOneWidget,
          );
          expect(
            find.text(
              'Not loaded yet. Open this source in IPTV, or refresh it here.',
            ),
            findsOneWidget,
          );
        }
        final dynamic category = t.widget(f.row('Category order'));
        category.onTap();
        final dynamic def = t.widget(f.row('Default playlist'));
        def.onTap();
        expect(f.events, [
          'category $kind',
          'default $kind',
        ], reason: 'original source object callbacks');
      });
    });
  }
  testWidgets(
    'busy refresh remains focusable with neutered pointer and remote tap',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.playlists = [twoPaneSource('a')];
        f.refreshingIds = {'a'};
        await f.mount(t);
        final dynamic row = t.widget(f.row('Refreshing…'));
        final node = row.focusNode as FocusNode;
        expect(
          node.canRequestFocus,
          isTrue,
          reason: 'busy row remains focusable',
        );
        node.requestFocus();
        await f.frame(t);
        await f.keyEvent(t, LogicalKeyboardKey.enter);
        await f.mouse(t, t.getCenter(f.row('Refreshing…')), click: true);
        expect(f.events, isEmpty, reason: 'busy refresh action neutered');
      });
    },
  );
  testWidgets(
    'lists Favorites skipped and order list create callbacks stay available',
    (t) async {
      await twoPaneCase(t, (f) async {
        await f.mount(t);
        await f.destination(t, 'Channel lists');
        expect(titles(t, f), [
          'Favorites',
          'Channel order',
          'News list',
          'Sports list',
          'Create list',
        ]);
        final favoriteFocus = t.widget<Focus>(
          find
              .descendant(of: f.row('Favorites'), matching: find.byType(Focus))
              .first,
        );
        expect(
          favoriteFocus.canRequestFocus,
          isFalse,
          reason: 'Favorites never focusable',
        );
        expect(favoriteFocus.descendantsAreFocusable, isFalse);
        await f.keyEvent(t, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-pane-0',
          reason: 'first actionable attached pane node',
        );
        await f.keyEvent(t, LogicalKeyboardKey.enter);
        final dynamic news = t.widget(f.row('News list'));
        news.onTap();
        final dynamic create = t.widget(f.row('Create list'));
        create.onTap();
        expect(f.events, ['channel-order', 'list news', 'create-list']);
        expect(find.text('1 channel'), findsOneWidget);
        expect(find.text('2 channels'), findsOneWidget);
        await f.keyEvent(t, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-rail-4',
        );
      });
    },
  );
  for (final enabled in [false, true]) {
    for (final pinned in [false, true]) {
      testWidgets('startup conditions enabled=$enabled pinned=$pinned', (
        t,
      ) async {
        await twoPaneCase(t, (f) async {
          f.startupEnabled = enabled;
          f.startupMode = pinned
              ? StartupIptvStorage.startupIptvModePinned
              : StartupIptvStorage.startupIptvModeLast;
          await f.mount(t);
          await f.destination(t, 'Startup channel');
          expect(titles(t, f), [
            'Start on a channel',
            if (enabled) ...[
              'Last watched channel',
              'A specific channel',
              if (pinned) 'Change channel',
            ],
          ], reason: 'startup row conditions');
          if (enabled) {
            expect(find.text('Currently: CH 9 · Last live'), findsOneWidget);
            f.hasLastLiveChannel = false;
            f.hasStartupChannel = false;
            await f.refresh(t);
            expect(find.textContaining('Nothing watched yet'), findsOneWidget);
            expect(
              find.text('Choose channel'),
              pinned ? findsOneWidget : findsNothing,
            );
          }
        });
      });
    }
  }
  for (final toggle in [false, true]) {
    for (final engine in [false, true]) {
      for (final count in [0, 3]) {
        for (final battery in [null, false, true]) {
          testWidgets(
            'recording conditions toggle=$toggle engine=$engine count=$count battery=$battery',
            (t) async {
              await twoPaneCase(t, (f) async {
                f.showEngineToggle = toggle;
                f.engine = engine;
                f.scheduledCount = count;
                f.batteryExempt = battery;
                await f.mount(t);
                await f.destination(t, 'Recording');
                final active = !toggle || engine;
                expect(titles(t, f), [
                  if (toggle) 'Background recording engine',
                  if (active) ...[
                    'Simultaneous recordings',
                    if (battery != null) 'Battery optimization',
                    'Recordings',
                  ],
                ], reason: 'recording row conditions');
                final dynamic rail = f
                    .rails(t)
                    .firstWhere((e) => e.title == 'Recording');
                final expected = !toggle
                    ? (count == 0 ? 'Recordings' : '3 scheduled')
                    : engine
                    ? (count == 0 ? 'Engine on' : 'Engine on · 3 scheduled')
                    : 'Player-tied';
                expect(
                  rail.subtitle,
                  expected,
                  reason: 'recording rail subtitle',
                );
                if (active) {
                  expect(
                    find.text(
                      count == 0
                          ? 'Live captures, schedules and your recorded files'
                          : '3 scheduled · live captures and recorded files',
                    ),
                    findsOneWidget,
                  );
                  expect(
                    find.text(
                      '2 at a time — each is an extra provider connection',
                    ),
                    findsOneWidget,
                  );
                  if (battery != null) {
                    expect(
                      find.textContaining(
                        battery ? 'Excluded —' : 'Optimized —',
                      ),
                      findsOneWidget,
                    );
                  }
                }
              });
            },
          );
        }
      }
    }
  }
  testWidgets(
    'destination ListView keys separate pane scroll and layout width threshold',
    (t) async {
      await twoPaneCase(t, (f) async {
        for (final size in [
          const Size(1280, 800),
          const Size(1399, 900),
          const Size(1400, 900),
          const Size(1440, 900),
        ]) {
          await f.mount(t, size: size);
          final rail = t
              .widgetList<ListView>(find.byType(ListView))
              .firstWhere((w) => w.key == null);
          final rect = t.getRect(find.byWidget(rail));
          expect(
            rect.width,
            size.width >= 1400 ? 400 : 330,
            reason: 'rail width boundary',
          );
          final group = t.widget<FocusTraversalGroup>(
            find.byType(FocusTraversalGroup).last,
          );
          expect(group.policy, isA<WidgetOrderTraversalPolicy>());
          await f.destination(t, 'Channel lists');
          expect(f.paneKey, 'lists');
          final list = t.widget<ListView>(find.byKey(const ValueKey('lists')));
          expect(list.padding, const EdgeInsets.fromLTRB(28, 22, 28, 32));
          await f.destination(t, 'Source c');
          expect(f.paneKey, 'source:c');
          expect(f.key.currentState, isNotNull);
        }
      });
    },
  );
  testWidgets(
    'pane row repeats LEFT and OK switch pointer fires once on provided node',
    (t) async {
      await twoPaneCase(t, (f) async {
        await f.mount(t);
        await f.destination(t, 'Channel preview');
        final dynamic row = t.widget(f.row('Play channel previews'));
        final node = row.focusNode as FocusNode;
        await f.keyEvent(t, LogicalKeyboardKey.arrowRight);
        await f.repeat(t, LogicalKeyboardKey.enter);
        expect(f.events, [
          'preview false',
          'preview false',
        ], reason: 'pane row KeyRepeat OK');
        f.events.clear();
        await f.destination(t, 'Channel preview');
        await f.mouse(t, t.getCenter(find.byType(Switch)), click: true);
        expect(f.events, [
          'preview false',
        ], reason: 'Switch pointer action fires once');
        expect(
          node.hasPrimaryFocus,
          isTrue,
          reason: 'pointer focuses provided pane node',
        );
        f.escapedKeys.clear();
        await t.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
        await f.frame(t);
        node.requestFocus();
        await f.frame(t);
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
        await f.frame(t);
        await t.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-rail-6',
          reason: 'pane row repeated LEFT returns to rail',
        );
      });
    },
  );
  testWidgets(
    'method cards horizontal grammar repeat and last RIGHT consumed',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.openAddSource = true;
        await f.mount(t);
        f.key.currentState!.focusAddPane();
        await f.frame(t);
        await f.repeat(t, LogicalKeyboardKey.arrowRight);
        expect(
          f.xtream.hasPrimaryFocus,
          isTrue,
          reason: 'method card KeyRepeat RIGHT',
        );
        f.escapedKeys.clear();
        await f.keyEvent(t, LogicalKeyboardKey.arrowRight);
        expect(f.escapedKeys, isEmpty, reason: 'last method RIGHT consumed');
        await f.keyEvent(t, LogicalKeyboardKey.enter);
        expect(f.events, ['method 2']);
        await f.keyEvent(t, LogicalKeyboardKey.arrowLeft);
        expect(f.file.hasPrimaryFocus, isTrue);
        await f.keyEvent(t, LogicalKeyboardKey.arrowLeft);
        expect(f.url.hasPrimaryFocus, isTrue);
        await f.keyEvent(t, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-2p-rail-3',
        );
        await f.mouse(
          t,
          t.getCenter(f.pieces('MethodCard').at(1)),
          click: true,
        );
        expect(
          f.file.hasPrimaryFocus,
          isTrue,
          reason: 'method pointer focuses host node',
        );
        expect(f.events, ['method 2', 'method 1']);
      });
    },
  );
  testWidgets('null Auto-refresh action keeps its only row unfocusable', (
    t,
  ) async {
    await twoPaneCase(t, (f) async {
      f.autoRefreshAction = false;
      await f.mount(t);
      await f.destination(t, 'Auto-refresh');
      await f.keyEvent(t, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'iptv-2p-rail-11');
      final focus = t.widget<Focus>(
        find.descendant(of: f.paneRows, matching: find.byType(Focus)).first,
      );
      expect(
        focus.canRequestFocus,
        isFalse,
        reason: 'legacy null Auto-refresh action',
      );
    });
  });
}
