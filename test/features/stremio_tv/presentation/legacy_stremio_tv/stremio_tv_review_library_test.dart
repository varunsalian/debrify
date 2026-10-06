import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/screens/stremio_tv/stremio_tv_filter_page.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/stremio_tv_fixture.dart';
import '../../../../support/stremio_tv_preferences.dart';

void main() {
  testWidgets(
    'C5 (R/O) favorite restores captured channel after intervening focus',
    (t) async {
      await stremioTvCase(t, (f) async {
        await f.mount(t);
        final selected = f.node('stremioTvRow1');
        selected.requestFocus();
        await f.settle(t);
        final held = await t.runAsync(StremioTvHeldPreferences.install);
        try {
          f.tuner(t).onToggleFavorite(f.channel(t, 2));
          await f.until(t, () => held!.ready.isCompleted);
          final other = f.node('stremioTvRow0');
          other.requestFocus();
          await f.settle(t);
          expect(other.hasPrimaryFocus, isTrue);
          held!.release.complete();
          await f.until(t, () => f.channel(t, 2).isFavorite);
          await f.settle(t);
          expect(f.tuner(t).channels.first.id, f.channelId(2));
          expect(
            FocusManager.instance.primaryFocus,
            same(selected),
            reason:
                'post-frame favorite callback restores the captured channel',
          );
        } finally {
          if (!held!.release.isCompleted) held.release.complete();
        }
      });
    },
  );

  testWidgets('C6 (R/O) editor with no visible channels focuses search', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.count = 1;
      await f.mount(t);
      f.tuner(t).onEditLocal!(f.channel(t));
      await f.until(
        t,
        () => find
            .byType(StremioTvLocalCatalogEditorDialog)
            .evaluate()
            .isNotEmpty,
      );
      await t.runAsync(
        () => StremioCatalogStorage.setStremioTvLocalCatalogs([]),
      );
      final held = await t.runAsync(StremioTvHeldPreferences.install);
      try {
        f.navigator.currentState!.pop(true);
        await f.until(t, () => held!.ready.isCompleted);
        f.node('menuBtn').requestFocus();
        await f.settle(t);
        expect(f.node('menuBtn').hasPrimaryFocus, isTrue);
        held!.release.complete();
        await f.until(
          t,
          () => find.text('No Catalog Addons').evaluate().isNotEmpty,
        );
        await f.settle(t);
        expect(
          f.node('searchBtn').hasPrimaryFocus,
          isTrue,
          reason: 'editor empty-library post-frame fallback focuses search',
        );
      } finally {
        if (!held!.release.isCompleted) held.release.complete();
      }
    });
  });

  testWidgets('C5 (R) genre-only query matches public channel model genre', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      final channels = f.tuner(t).allChannels;
      final original = channels.first;
      // Public mutable model boundary: the genre is independent of displayName.
      // Production factories normally duplicate it in the name, masking this
      // branch. This valid channel input exercises the separate genre contract.
      channels[0] = StremioTvChannel(
        id: original.id,
        displayName: original.displayName,
        addon: original.addon,
        catalog: original.catalog,
        channelNumber: original.channelNumber,
        genre: 'GenreOnlyNoir',
        isLocal: original.isLocal,
        items: original.items,
      );
      expect(
        original.displayName.toLowerCase(),
        isNot(contains('genreonlynoir')),
      );
      f.node('searchBtn').requestFocus();
      await t.pump();
      await f.key(t, LogicalKeyboardKey.enter);
      await t.enterText(find.byType(EditableText), 'genreonlynoir');
      await f.settle(t);
      expect(
        find.byType(StremioTvTuner),
        findsOneWidget,
        reason: 'genre-only search keeps its matching channel visible',
      );
      expect(
        f.tuner(t).channels.map((c) => c.id),
        [original.id],
        reason: 'genre-only search selects its channel independently of names',
      );
    });
  });

  testWidgets(
    'C8 (R) empty search Escape restores search rather than prior menu',
    (t) async {
      await stremioTvCase(t, (f) async {
        await f.mount(t);
        f.node('searchBtn').requestFocus();
        await t.pump();
        await f.key(t, LogicalKeyboardKey.enter);
        await t.enterText(find.byType(EditableText), 'original');
        await f.settle(t);
        await f.key(t, LogicalKeyboardKey.escape);
        expect(
          t.widget<EditableText>(find.byType(EditableText)).controller.text,
          isEmpty,
        );
        // Change the scope's fallback history; automatic restoration to the
        // previous search-button node must not mask the screen's explicit call.
        f.node('menuBtn').requestFocus();
        await t.pump();
        t
            .widget<TvTextField>(find.byType(TvTextField))
            .focusNode!
            .requestFocus();
        await t.pump();
        expect(f.node('searchBtn').hasFocus, isFalse);
        await f.key(t, LogicalKeyboardKey.escape);
        expect(find.byType(EditableText), findsNothing);
        expect(
          FocusManager.instance.primaryFocus,
          same(f.node('searchBtn')),
          reason: 'empty-field Escape explicitly restores search-button focus',
        );
      });
    },
  );

  testWidgets('C6 (R/O) filter page receives stored disabled catalog', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      final disabled = {f.channelId(2)};
      await t.runAsync(
        () => StremioTvStorage.setStremioTvDisabledFilters(disabled),
      );
      await f.mount(t);
      expect(f.tuner(t).channels.map((c) => c.id), [f.channelId(1)]);
      await f.menu(t);
      await f.tap(t, find.widgetWithText(MenuItemButton, 'Filter channels'));
      final page = t.widget<StremioTvFilterPage>(
        find.byType(StremioTvFilterPage),
      );
      expect(
        page.disabledFilters,
        disabled,
        reason: 'filter route preserves stored disabled catalog',
      );
      expect(find.text('Original channel 2'), findsOneWidget);
      f.navigator.currentState!.pop(false);
      await f.settle(t);
    });
  });
}
