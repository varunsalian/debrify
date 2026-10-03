import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_results_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'SQL first present consumes the stored landing seed',
    (tester) => iptvResultsCase(tester, (view) async {
      expect(IptvCatalogDb.setDefaultCategory(view.catalogKey, 'Kids'), isTrue);
      await view.mount(tester);
      final access = iptvResultsViewTestAccess(view.state);
      expect(access.selectedCategory, 'Kids');
      expect(access.filteredChannels.map((channel) => channel.group).toSet(), {
        'Kids',
      });
      expect(access.landingSeedArmed, isFalse);
      expect(access.categoryManuallyChosen, isFalse);
    }, numbered: true),
  );

  testWidgets(
    'manual All survives a published SQL revalidation without reseeding',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      iptvResultsViewTestAccess(view.state).chooseCategory(null);
      await tester.pump();
      expect(
        IptvCatalogDb.setDefaultCategory(view.catalogKey, 'Culture'),
        isTrue,
      );
      final fresh = view.ingest(view.channels);
      await view.notifyRefresh(tester, fresh);
      final access = iptvResultsViewTestAccess(view.state);
      expect(access.selectedCategory, isNull);
      expect(access.filteredChannels.length, 12);
      expect(access.categoryManuallyChosen, isTrue);
      expect(access.landingSeedArmed, isFalse);
    }, numbered: true),
  );

  testWidgets(
    'unchanged digest without numbering retains facades, instances and focus',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      final before = iptvResultsViewTestAccess(view.state);
      final channel = before.filteredChannels.first;
      final focus = before.focusNodeFor(channel);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      final fresh = view.ingest(view.channels, numbered: false);
      expect(fresh.contentDigest, before.snapshot!.contentDigest);
      await view.notifyRefresh(tester, fresh);
      final after = iptvResultsViewTestAccess(view.state);
      expect(after.allChannels, same(before.allChannels));
      expect(after.filteredChannels, same(before.filteredChannels));
      expect(after.filteredChannels.first, same(channel));
      expect(after.focusNodes[channel], same(focus));
      expect(focus.hasFocus, isTrue);
    }, numbered: false),
  );

  testWidgets(
    'unchanged digest with a vanished category replaces the filtered facade',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      iptvResultsViewTestAccess(view.state).chooseCategory('Kids');
      await tester.pump();
      final before = iptvResultsViewTestAccess(view.state);
      final fresh = view.ingest(
        view.channels,
        numbered: false,
        categories: ['News', 'Culture'],
      );
      expect(fresh.contentDigest, before.snapshot!.contentDigest);
      await view.notifyRefresh(tester, fresh);
      final after = iptvResultsViewTestAccess(view.state);
      expect(after.selectedCategory, isNull);
      expect(after.allChannels, same(before.allChannels));
      expect(
        identical(after.filteredChannels, before.filteredChannels),
        isFalse,
      );
      expect(after.filteredChannels.length, 12);
    }, numbered: false),
  );

  testWidgets(
    'new numbering takes the changed path even when digest is unchanged',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      final before = iptvResultsViewTestAccess(view.state);
      expect(before.allChannels.first.channelNumber, isNull);
      final fresh = view.ingest(view.channels);
      expect(fresh.contentDigest, before.snapshot!.contentDigest);
      await view.notifyRefresh(tester, fresh);
      final after = iptvResultsViewTestAccess(view.state);
      expect(after.allChannels.first.channelNumber, isNotNull);
      expect(identical(after.allChannels, before.allChannels), isFalse);
      expect(
        identical(after.filteredChannels, before.filteredChannels),
        isFalse,
      );
    }, numbered: false),
  );

  List<IptvChannel> changedRows(IptvResultsFixture view) => [
    for (final channel in view.channels.reversed)
      IptvChannel(
        name: '${channel.name} refreshed',
        url: channel.url,
        group: channel.group,
        duration: channel.duration,
        contentType: channel.contentType,
        attributes: channel.attributes,
        httpHeaders: channel.httpHeaders,
      ),
  ];

  testWidgets(
    'changed digest repairs focus at the same index rather than following the URL',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      iptvResultsViewTestAccess(view.state).chooseCategory(null);
      await tester.pump();
      final before = iptvResultsViewTestAccess(view.state);
      const index = 2;
      final oldChannel = before.filteredChannels[index];
      before.focusNodeFor(oldChannel).requestFocus();
      await tester.pump();
      expect(before.focusNodes[oldChannel]!.hasFocus, isTrue);
      final fresh = view.ingest(changedRows(view));
      await view.notifyRefresh(tester, fresh);
      final after = iptvResultsViewTestAccess(view.state);
      final candidate = after.filteredChannels[index];
      expect(candidate.url, isNot(oldChannel.url));
      expect(after.focusNodes[candidate]!.hasFocus, isTrue);
    }, numbered: true),
  );

  testWidgets(
    'changed digest leaves focus elsewhere alone',
    (tester) => iptvResultsCase(tester, (view) async {
      final external = FocusNode(debugLabel: 'external-contract-action');
      addTearDown(external.dispose);
      await view.mount(tester, externalFocus: external);
      external.requestFocus();
      await tester.pump();
      final fresh = view.ingest(changedRows(view));
      await view.notifyRefresh(tester, fresh);
      expect(external.hasPrimaryFocus, isTrue);
    }, numbered: true),
  );

  testWidgets(
    'a stale published-refresh ticket cannot replace the SQL view',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      final before = iptvResultsViewTestAccess(view.state);
      final fresh = view.ingest(changedRows(view));
      await tester.runAsync(
        () => before.refreshCatalog(
          before.selectedPlaylist!,
          'live',
          view.catalogKey,
          before.loadTicket - 1,
          usePublishedSnapshot: true,
        ),
      );
      await tester.pump();
      final stale = iptvResultsViewTestAccess(view.state);
      expect(stale.snapshot, same(before.snapshot));
      expect(stale.allChannels, same(before.allChannels));
      expect(stale.filteredChannels, same(before.filteredChannels));
      await view.notifyRefresh(tester, fresh);
      expect(
        iptvResultsViewTestAccess(view.state).snapshot!.generation,
        fresh.generation,
      );
    }, numbered: true),
  );

  testWidgets(
    'query debounce is cancelled by a newer query and disposal',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      await view.mount(tester, query: 'Channel 11');
      await tester.pump(const Duration(milliseconds: 100));
      await view.mount(tester, query: 'Channel 2');
      await tester.pump(const Duration(milliseconds: 221));
      final channels = iptvResultsViewTestAccess(view.state).filteredChannels;
      await view.until(tester, () => channels.isNotEmpty);
      expect(channels.map((channel) => channel.name), ['Channel 2']);
      await view.mount(tester, query: 'Channel 3');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 221));
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'pending catalog presentation completes safely after unmount',
    (tester) => iptvResultsCase(tester, (view) async {
      await view.mount(tester);
      final access = iptvResultsViewTestAccess(view.state);
      final future = access.presentDbCatalog(
        access.selectedPlaylist!,
        access.loadTicket,
        access.snapshot!,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      var completed = false;
      future.whenComplete(() => completed = true);
      await view.until(tester, () => completed);
      await future;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(view.key.currentState, isNull);
    }, numbered: true),
  );
}
