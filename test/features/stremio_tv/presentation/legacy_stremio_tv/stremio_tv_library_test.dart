import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/stremio_tv_fixture.dart';
import '../../../../support/stremio_tv_preferences.dart';

void main() {
  testWidgets(
    'C5 (R/O) items land rebuild only tuner and retain screen widget',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.count = 1;
        f.addonCatalogs = [
          {'id': 'revision', 'type': 'movie', 'name': 'Revision'},
        ];
        final held = Completer<http.Response>();
        f.onRequest = (r) => r.url.path.contains('/catalog/')
            ? held.future
            : f.providerResponse(r);
        await f.mount(t);
        final addon = f.tuner(t).allChannels.singleWhere((c) => !c.isLocal);
        expect(addon.items, isEmpty);
        f.tuner(t).ensureLoaded(addon);
        await f.until(
          t,
          () => f.requests.any((r) => r.url.path.contains('/catalog/')),
        );
        final beforeTuner = f.tuner(t);
        final beforeScreen = t.widget<Scaffold>(find.byType(Scaffold).first);
        held.complete(
          f.jsonResponse({
            'metas': [f.meta(1).toJson()],
          }),
        );
        await f.settle(t, frames: 40);
        expect(addon.hasItems, isTrue);
        expect(f.tuner(t), isNot(same(beforeTuner)));
        expect(
          t.widget<Scaffold>(find.byType(Scaffold).first),
          same(beforeScreen),
        );
      });
    },
  );
  testWidgets(
    'C5 (R/O) favourite discovery sorts first and toggle preserves focused channel',
    (t) async {
      await stremioTvCase(t, (f) async {
        await t.runAsync(
          () => StremioTvStorage.setStremioTvChannelFavorited(
            f.channelId(2),
            true,
          ),
        );
        await f.mount(t);
        expect(f.tuner(t).channels.map((c) => c.id), [
          f.channelId(2),
          f.channelId(1),
        ]);
        final channel = f.channel(t, 2);
        // Row zero represents the already-favourited channel after discovery.
        final focused = f.node('stremioTvRow0');
        focused.requestFocus();
        await f.settle(t);
        f.tuner(t).onToggleFavorite(channel);
        await f.until(t, () => !f.channel(t, 2).isFavorite);
        expect(
          await t.runAsync(StremioTvStorage.getStremioTvFavoriteChannelIds),
          isNot(contains(channel.id)),
        );
        expect(f.tuner(t).channels.map((c) => c.id), [
          f.channelId(1),
          f.channelId(2),
        ]);
        expect(focused.hasFocus, isTrue);
      });
    },
  );

  testWidgets('C5 (O) refresh is single flight while preferences are held', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      await f.menu(t);
      final refresh = t
          .widget<MenuItemButton>(
            find.widgetWithText(MenuItemButton, 'Refresh'),
          )
          .onPressed!;
      final held = await t.runAsync(StremioTvHeldPreferences.install);
      try {
        refresh();
        refresh();
        await f.settle(t, frames: 40);
        expect(
          held!.ready.isCompleted,
          isTrue,
          reason: 'Refresh starts the held discovery read',
        );
        await f.settle(t);
        expect(
          t
              .widget<MenuItemButton>(
                find.widgetWithText(MenuItemButton, 'Refresh'),
              )
              .onPressed,
          isNull,
        );
        expect(held.reads, 1);
      } finally {
        held!.release.complete();
      }
      await f.until(
        t,
        () =>
            t
                .widget<MenuItemButton>(
                  find.widgetWithText(MenuItemButton, 'Refresh'),
                )
                .onPressed !=
            null,
      );
      expect(f.tuner(t).allChannels, hasLength(2));
    });
  });

  testWidgets(
    'C6/C8 (R) menu and Import order connection gate and focus return',
    (t) async {
      await stremioTvCase(t, (f) async {
        await f.mount(t);
        await f.menu(t);
        final top = t
            .widgetList<MenuItemButton>(find.byType(MenuItemButton))
            .map((b) => (b.child as Text).data)
            .toList();
        expect(top, [
          'Shuffle (Mix 1)',
          'Refresh',
          'Filter channels',
          'Stremio TV Settings',
        ]);
        f.node('localCatalogs').requestFocus();
        await f.key(t, LogicalKeyboardKey.arrowRight);
        expect(find.text('From MDBList'), findsNothing);
        final entries = t
            .widgetList<MenuItemButton>(find.byType(MenuItemButton))
            .map((b) => (b.child as Text).data)
            .toList();
        expect(entries.skip(4), [
          'Manage',
          'From File',
          'From URL',
          'Paste JSON',
          'From Repository',
          'From Trakt',
        ]);
        await f.key(t, LogicalKeyboardKey.arrowLeft);
        expect(f.node('localCatalogs').hasFocus, isTrue);
        await f.key(t, LogicalKeyboardKey.escape);
        expect(f.node('menuBtn').hasFocus, isTrue);
        await t.runAsync(
          () => MdblistStorage.saveMdblistApiKey('original-mdblist'),
        );
        // Auth is read once per mount; a new route instance observes the key.
        await t.pumpWidget(const SizedBox());
        await f.settle(t);
        await t.pumpWidget(f.host());
        await f.until(
          t,
          () => find.byType(StremioTvTuner).evaluate().isNotEmpty,
        );
        await f.settle(t);
        await f.menu(t);
        f.node('localCatalogs').requestFocus();
        await f.key(t, LogicalKeyboardKey.arrowRight);
        expect(find.text('From MDBList'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'C6 (R/O) local export writes original catalog JSON and snackbar',
    (t) async {
      await stremioTvCase(t, (f) async {
        await f.mount(t);
        f.tuner(t).onExportLocal!(f.channel(t));
        await f.until(t, () => f.clipboard.isNotEmpty);
        final payload = jsonDecode(f.clipboard.single) as Map;
        expect(payload['name'], 'Original channel 1');
        expect((payload['items'] as List).single['id'], f.meta(1).id);
        expect(
          find.text('Copied "Original channel 1" JSON to clipboard'),
          findsOneWidget,
        );
      });
    },
  );

  testWidgets('C7 (O) detail route fields and double-open reentrancy', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      final tuner = f.tuner(t);
      tuner.onOpenDetail(f.channel(t));
      tuner.onOpenDetail(f.channel(t));
      await f.until(t, () => f.observer.details.isNotEmpty);
      expect(f.observer.details, hasLength(1));
      expect(f.observer.details.single.isTelevision, isTrue);
      expect(f.observer.details.single.enablePrimarySourcesHold, isFalse);
      expect(find.byType(CatalogItemDetailScreen), findsNothing);
      f.observer.details.single.onPlay();
      await f.until(t, () => f.observer.players.isNotEmpty);
    });
  });

  testWidgets('C7 (R/O) in-flight detail waits on poll and guide tap plays', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.count = 20;
      f.addonCatalogs = [
        {'id': 'detail-unloaded', 'type': 'movie', 'name': 'Detail unloaded'},
      ];
      await t.runAsync(() async {
        for (var i = 1; i <= f.count; i++) {
          await StremioTvStorage.setStremioTvChannelFavorited(
            f.channelId(i),
            true,
          );
        }
      });
      await f.mount(t);
      final addon = f.tuner(t).allChannels.singleWhere((c) => !c.isLocal);
      expect(addon.hasItems, isFalse);
      final held = Completer<http.Response>();
      f.onRequest = (r) => r.url.path.contains('/catalog/')
          ? held.future
          : f.providerResponse(r);
      f.tuner(t).ensureLoaded(addon);
      await f.until(
        t,
        () => f.requests.any((r) => r.url.path.contains('/catalog/')),
      );
      f.tuner(t).onOpenDetail(addon);
      await f.settle(t, frames: 1);
      expect(f.observer.details, isEmpty);
      held.complete(
        f.jsonResponse({
          'metas': [f.meta(1).toJson()],
        }),
      );
      await f.settle(t, frames: 40);
      expect(f.observer.details, hasLength(1));
      expect(f.observer.details.single.item.id, f.meta(1).id);
      f.tuner(t).onShowGuide(f.channel(t));
      await f.settle(t);
      expect(find.text(f.meta(1).name), findsWidgets);
      await f.tap(
        t,
        find
            .descendant(
              of: find.byType(StremioTvGuideSheet),
              matching: find.text(f.meta(1).name),
            )
            .first,
      );
      await f.until(t, () => f.observer.players.isNotEmpty);
    });
  });
}
