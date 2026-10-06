import 'dart:async';

import 'package:debrify/screens/settings/stremio_tv_settings_page.dart';
import 'package:debrify/screens/stremio_tv/stremio_tv_filter_page.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/stremio_tv_fixture.dart';

void main() {
  testWidgets('C4 (O) settings route return reloads persisted settings', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      expect(f.tuner(t).hideNowPlaying, isFalse);
      await f.menu(t);
      await f.tap(
        t,
        find.widgetWithText(MenuItemButton, 'Stremio TV Settings'),
      );
      expect(find.byType(StremioTvSettingsPage), findsOneWidget);
      await t.runAsync(() => StremioTvStorage.setStremioTvHideNowPlaying(true));
      f.navigator.currentState!.pop();
      await f.settle(t, frames: 40);
      expect(f.tuner(t).hideNowPlaying, isTrue);
      expect(
        await t.runAsync(StremioTvStorage.getStremioTvHideNowPlaying),
        isTrue,
      );
    });
  });

  testWidgets('C6 (O) filter page true return refreshes production discovery', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      await f.menu(t);
      await f.tap(t, find.widgetWithText(MenuItemButton, 'Filter channels'));
      expect(find.byType(StremioTvFilterPage), findsOneWidget);
      await t.runAsync(
        () => StremioTvStorage.setStremioTvDisabledFilters({'local'}),
      );
      f.navigator.currentState!.pop(true);
      await f.settle(t, frames: 40);
      expect(find.text('No Catalog Addons'), findsOneWidget);
    });
  });

  testWidgets(
    'C6 (R/O) local editor saves renamed catalog and refocuses edited channel',
    (t) async {
      await stremioTvCase(t, (f) async {
        await f.mount(t);
        f.node('stremioTvRow1').requestFocus();
        await f.settle(t);
        f.tuner(t).onEditLocal!(f.channel(t));
        await f.until(
          t,
          () => find
              .byType(StremioTvLocalCatalogEditorDialog)
              .evaluate()
              .isNotEmpty,
        );
        await f.settle(t);
        // The dialog's Save result is the screen's boundary; edit its production
        // storage before that result so refresh/refocus sees the new snapshot.
        await t.runAsync(() async {
          final catalogs =
              await StremioCatalogStorage.getStremioTvLocalCatalogs();
          catalogs.first['name'] = 'Renamed original';
          await StremioCatalogStorage.setStremioTvLocalCatalogs(catalogs);
        });
        f.navigator.currentState!.pop(true);
        await f.until(
          t,
          () => f
              .tuner(t)
              .allChannels
              .first
              .displayName
              .contains('Renamed original'),
        );
        await f.settle(t);
        expect(f.node('stremioTvRow0').hasFocus, isTrue);
        expect(f.tuner(t).channels.first.id, f.channelId(1));
      });
    },
  );

  testWidgets(
    'C5 (R/O) empty lazy channel is removed and focus chooses previous neighbour',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.count = 20;
        f.addonCatalogs = [
          {'id': 'empty-focus', 'type': 'movie', 'name': 'Empty focus'},
        ];
        await t.runAsync(() async {
          for (var i = 1; i <= 10; i++) {
            await StremioTvStorage.setStremioTvChannelFavorited(
              f.channelId(i),
              true,
            );
          }
        });
        final held = Completer<http.Response>();
        f.onRequest = (r) => r.url.path.contains('/catalog/')
            ? held.future
            : f.providerResponse(r);
        await f.mount(t);
        final addon = f.tuner(t).allChannels.singleWhere((c) => !c.isLocal);
        expect(f.tuner(t).channels.indexOf(addon), 10);
        f.node('stremioTvRow10').requestFocus();
        await f.settle(t);
        f.tuner(t).ensureLoaded(addon);
        await f.until(
          t,
          () => f.requests.any((r) => r.url.path.contains('/catalog/')),
        );
        held.complete(f.jsonResponse({'metas': []}));
        await f.until(t, () => f.tuner(t).allChannels.length == 20);
        await f.settle(t);
        expect(f.node('stremioTvRow9').hasFocus, isTrue);
        expect(f.tuner(t).allChannels.any((c) => c.id == addon.id), isFalse);
      });
    },
  );

  testWidgets('C8 (R) provider menu Escape restores the anchor focus', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      f.node('providerBtn').requestFocus();
      await t.pump();
      await f.key(t, LogicalKeyboardKey.enter);
      expect(find.text('Auto (Real-Debrid)'), findsOneWidget);
      await f.key(t, LogicalKeyboardKey.escape);
      expect(find.text('Auto (Real-Debrid)'), findsNothing);
      expect(f.node('providerBtn').hasFocus, isTrue);
    });
  });
}
