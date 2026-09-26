import 'package:debrify/features/sources/application/source_results_controller.dart';
import 'package:debrify/features/sources/application/source_seasons_dependencies.dart';
import 'package:debrify/features/sources/models/source_results_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(
  String hash, {
  String name = 'Row',
  String? url,
  bool realHash = true,
}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  hasRealInfoHash: realHash,
  directUrl: url,
);

void main() {
  late ProviderContainer container;
  late SourcesSession session;
  late ProviderSubscription<SourceResultsState> subscription;
  late SourceResultsController controller;
  setUp(() {
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: const AdvancedSearchSelection(
        imdbId: 'tt1',
        isSeries: false,
        title: 'One',
      ),
    );
    container = ProviderContainer.test();
    subscription = container.listen(sourceResultsProvider(session), (_, _) {});
    controller = container.read(sourceResultsProvider(session).notifier);
  });

  test(
    'live rows adopt until interaction, then replace only the pending set',
    () {
      final first = row('first');
      final second = row('second');
      expect(controller.bufferIfFrozen([first]), isFalse);
      controller.display([first]);
      controller.freeze();
      expect(controller.bufferIfFrozen([first, second]), isTrue);
      expect(subscription.read().displayed, [same(first)]);
      expect(subscription.read().pending, [same(first), same(second)]);
      expect(subscription.read().pendingNewCount, 1);
      final replacement = row('replacement');
      controller.bufferIfFrozen([replacement]);
      expect(subscription.read().pending, [same(replacement)]);
      expect(subscription.read().displayed, [same(first)]);
      controller.display(subscription.read().pending!);
      expect(subscription.read().displayed, [same(replacement)]);
      expect(subscription.read().pending, isNull);
      expect(subscription.read().pendingNewCount, 0);
      expect(subscription.read().frozen, isTrue);
    },
  );

  test('new search clears adopted and pending rows and resumes streaming', () {
    controller.display([row('old')]);
    controller.freeze();
    controller.bufferIfFrozen([row('pending')]);
    controller.beginSearch();
    expect(subscription.read().displayed, isEmpty);
    expect(subscription.read().pending, isNull);
    expect(subscription.read().frozen, isFalse);
    expect(controller.bufferIfFrozen([row('new')]), isFalse);
  });

  test(
    'published lists snapshot inputs without cloning Torrent identities',
    () {
      final torrent = row('one');
      final input = [torrent];
      controller.display(input);
      input.clear();
      expect(subscription.read().displayed, [same(torrent)]);
      expect(
        () => subscription.read().displayed.clear(),
        throwsUnsupportedError,
      );
      controller.freeze();
      input.add(torrent);
      controller.bufferIfFrozen(input);
      input.clear();
      expect(subscription.read().pending, [same(torrent)]);
      expect(
        () => subscription.read().pending!.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'pill uses case-insensitive real hashes, not list length differences',
    () {
      controller.display([row('ABC'), row('gone'), row('also gone')]);
      controller.freeze();
      controller.bufferIfFrozen([row('abc'), row('new')]);
      expect(subscription.read().pendingNewCount, 1);
    },
  );

  test(
    'hashless identity includes name and URL; repeated new rows still count',
    () {
      controller.display([
        row('synthetic', name: 'A', url: 'one', realHash: false),
      ]);
      controller.freeze();
      controller.bufferIfFrozen([
        row('other synthetic', name: 'A', url: 'one', realHash: false),
        row('synthetic', name: 'A', url: 'two', realHash: false),
        row('synthetic', name: 'B', url: 'one', realHash: false),
        row('synthetic', name: 'B', url: 'one', realHash: false),
      ]);
      expect(subscription.read().pendingNewCount, 3);
    },
  );

  test(
    'repeated freeze preserves a pending empty authoritative replacement',
    () {
      controller.display([row('one')]);
      controller.freeze();
      controller.bufferIfFrozen([]);
      controller.freeze();
      expect(subscription.read().pending, isEmpty);
      controller.display(subscription.read().pending!);
      expect(subscription.read().displayed, isEmpty);
      expect(subscription.read().pending, isNull);
      expect(subscription.read().frozen, isTrue);
    },
  );

  test('view instances with the same title own independent result state', () {
    final other = SourcesSession(
      owner: session.owner,
      viewIdentity: Object(),
      selection: session.selection,
    );
    final otherSubscription = container.listen(
      sourceResultsProvider(other),
      (_, _) {},
    );
    controller.display([row('one')]);
    controller.freeze();
    expect(otherSubscription.read().displayed, isEmpty);
    expect(otherSubscription.read().frozen, isFalse);
  });

  test(
    'profile retirement rejects actions and invalidation clears old rows',
    () {
      controller.display([row('private')]);
      final before = subscription.read();
      ProfileSessionMemory.clearAll();
      controller.display([row('late')]);
      controller.freeze();
      controller.beginSearch();
      expect(controller.bufferIfFrozen([row('late')]), isFalse);
      expect(subscription.read(), same(before));
      container.invalidate(sourcesSessionActiveProvider(session));
      expect(subscription.read().displayed, isEmpty);
      expect(subscription.read().pending, isNull);
    },
  );

  test('disposed controller rejects actions without accessing state', () {
    container.dispose();
    controller.beginSearch();
    controller.display([row('late')]);
    controller.freeze();
    expect(controller.bufferIfFrozen([row('late')]), isFalse);
  });
}
