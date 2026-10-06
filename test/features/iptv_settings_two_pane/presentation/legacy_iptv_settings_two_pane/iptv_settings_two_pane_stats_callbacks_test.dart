import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_settings_fixture.dart';
import '../../../../support/iptv_settings_two_pane_fixture.dart';

Future<void> seed(
  WidgetTester t,
  IptvSettingsTwoPaneFixture f,
  int count,
) async {
  final key = IptvCatalogKey.forPlaylist(f.playlists.single, 'live')!;
  await t.runAsync(
    () => IptvCatalogDb.ingestM3uLines(
      dbPath: IptvCatalogDb.path,
      catalogKey: key,
      lines: Stream.fromIterable([
        '#EXTM3U',
        for (var i = 0; i < count; i++) ...[
          '#EXTINF:-1 group-title="News",Channel $i',
          'https://fixture.invalid/$i.ts',
        ],
      ]),
    ),
  );
}

void main() {
  testWidgets(
    'stats cache retains unchanged signature and invalidates on password and refreshingIds',
    (t) async {
      await iptvSettingsCase(
        t,
        (db) async {
          await twoPaneCase(t, (f) async {
            f.playlists = [twoPaneSource('a')];
            f.defaultId = 'a';
            await seed(t, f, 1);
            await f.mount(t);
            expect(
              find.text('URL · 1 channel'),
              findsOneWidget,
              reason: 'seeded initial rail count',
            );
            expect(
              find.text('LIVE CHANNELS'),
              findsOneWidget,
              reason: 'cached stats strip rendered',
            );
            await seed(t, f, 2);
            await f.refresh(t);
            expect(
              find.text('URL · 1 channel'),
              findsOneWidget,
              reason: 'unchanged signature keeps old stats',
            );
            await f.focusIndex(t, 0);
            await f.destination(t, 'Channel lists');
            await f.destination(t, 'Source a');
            expect(
              find.text('URL · 1 channel'),
              findsOneWidget,
              reason: 'D-pad pane moves retain cache',
            );
            f.playlists = [twoPaneSource('a', password: 'changed-password')];
            await f.refresh(t);
            expect(
              find.text('URL · 2 channels'),
              findsOneWidget,
              reason: 'password-only signature invalidates stats',
            );
            await seed(t, f, 3);
            f.refreshingIds = {'a'};
            await f.refresh(t);
            expect(
              find.text('URL · 3 channels'),
              findsOneWidget,
              reason: 'refreshingIds-only signature invalidates stats',
            );
            expect(find.text('Refreshing…'), findsOneWidget);
          });
        },
        sources: [twoPaneSource('a')],
        singleProfile: true,
      );
    },
  );
  testWidgets(
    'host callback function objects and member tear-offs survive two builds',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.startupEnabled = true;
        f.startupMode = StartupIptvStorage.startupIptvModePinned;
        await f.mount(t);
        final dynamic rail = f.rails(t).first;
        final enter = rail.onSelect;
        expect(
          rail.onRight == enter,
          isTrue,
          reason: 'same State enterPane member',
        );
        dynamic firstLeft;
        dynamic methodDown;
        dynamic methodRight;
        for (var build = 0; build < 2; build++) {
          await f.destination(t, 'Startup channel');
          expect(
            identical(
              t.widget<Switch>(find.byType(Switch)).onChanged,
              f.toggleStartup,
            ),
            isTrue,
            reason: 'startup host function object',
          );
          expect(
            identical(
              (t.widget(f.row('Change channel')) as dynamic).onTap,
              f.pickStartup,
            ),
            isTrue,
          );
          final dynamic startup = t.widget(f.row('Start on a channel'));
          if (build == 0) {
            firstLeft = startup.onLeft;
          } else {
            expect(
              startup.onLeft == firstLeft,
              isTrue,
              reason: 'returnToRail tear-off same receiver across builds',
            );
          }
          await f.destination(t, 'Continue watching');
          expect(
            identical(
              t.widget<Switch>(find.byType(Switch)).onChanged,
              f.toggleTrack,
            ),
            isTrue,
          );
          await f.destination(t, 'Channel preview');
          expect(
            identical(
              t.widget<Switch>(find.byType(Switch)).onChanged,
              f.togglePreview,
            ),
            isTrue,
          );
          await f.destination(t, 'Recording');
          expect(
            identical(
              t.widget<Switch>(find.byType(Switch)).onChanged,
              f.toggleEngine,
            ),
            isTrue,
          );
          await f.destination(t, 'Auto-refresh');
          expect(
            identical(
              (t.widget(f.paneRows) as dynamic).onTap,
              f.pickAutoRefresh,
            ),
            isTrue,
          );
          await f.destination(t, 'Channel lists');
          expect(
            identical(
              (t.widget(f.row('Create list')) as dynamic).onTap,
              f.createList,
            ),
            isTrue,
          );
          expect(
            identical(
              (t.widget(f.row('Channel order')) as dynamic).onTap,
              f.manageOrder,
            ),
            isTrue,
          );
          await f.destination(t, 'Add a source');
          final cards = t
              .widgetList(f.pieces('MethodCard'))
              .cast<dynamic>()
              .toList();
          for (final card in cards) {
            expect(
              identical(card.onDown, f.focusForm),
              isTrue,
              reason: 'form-focus host object',
            );
          }
          expect(cards[0].onRight == f.file.requestFocus, isTrue);
          expect(cards[1].onLeft == f.url.requestFocus, isTrue);
          expect(cards[1].onRight == f.xtream.requestFocus, isTrue);
          expect(cards[2].onLeft == f.file.requestFocus, isTrue);
          if (build == 0) {
            methodDown = cards[0].onDown;
            methodRight = cards[0].onRight;
          } else {
            expect(identical(cards[0].onDown, methodDown), isTrue);
            expect(cards[0].onRight == methodRight, isTrue);
          }
          expect(
            f.rails(t).first.onSelect == enter,
            isTrue,
            reason: 'cached enterPane receiver across builds',
          );
          await f.refresh(t);
        }
      });
    },
  );
  testWidgets(
    'pooled and fallback row nodes dispose with original ownership and fallback click behaviour',
    (t) async {
      await twoPaneCase(t, (f) async {
        f.lists = [];
        await f.mount(t);
        await f.destination(t, 'Channel lists');
        final favorite = t
            .widget<Focus>(
              find
                  .descendant(
                    of: f.row('Favorites'),
                    matching: find.byType(Focus),
                  )
                  .first,
            )
            .focusNode!;
        final dynamic order = t.widget(f.row('Channel order'));
        final owned = order.focusNode as FocusNode;
        await f.destination(t, 'Source a');
        expect(
          () => favorite.addListener(() {}),
          throwsAssertionError,
          reason: 'lazy fallback node disposed when row unmounts',
        );
        expect(
          () => owned.addListener(() {}),
          returnsNormally,
          reason: 'pooled node retained across panes',
        );
        await t.pumpWidget(const SizedBox.shrink());
        expect(
          () => owned.addListener(() {}),
          throwsAssertionError,
          reason: 'pooled node disposed with State',
        );
        for (final node in f.methods) {
          expect(() => node.addListener(() {}), returnsNormally);
        }
      });
    },
  );
}
