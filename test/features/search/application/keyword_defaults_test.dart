import 'package:debrify/features/search/application/keyword_cache_dependencies.dart';
import 'package:debrify/features/search/application/keyword_defaults_dependencies.dart';
import 'package:debrify/features/search/application/keyword_results_controller.dart';
import 'package:debrify/features/search/application/keyword_search_dependencies.dart';
import 'package:debrify/features/search/models/keyword_results_state.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_keyword_cache_repository.dart';
import '../fakes/fake_keyword_defaults_repository.dart';
import '../fakes/fake_keyword_search_repository.dart';
import '../keyword_torrent_fixture.dart';

void main() {
  late FakeKeywordDefaultsRepository defaults;
  late ProviderContainer container;
  late KeywordResultsController controller;
  late ProviderSubscription<KeywordResultsState> subscription;
  late SearchSession key;
  final configured = TorrentFilterState(qualities: {QualityTier.fullHd});

  setUp(() {
    defaults = FakeKeywordDefaultsRepository();
    key = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container = ProviderContainer.test(
      overrides: [
        keywordDefaultsRepositoryProvider.overrideWith((ref, key) => defaults),
        keywordSearchRepositoryProvider.overrideWith(
          (ref, key) => FakeKeywordSearchRepository(),
        ),
        keywordCacheRepositoryProvider.overrideWith(
          (ref, key) => FakeKeywordCacheRepository(),
        ),
      ],
    );
    subscription = container.listen(keywordResultsProvider(key), (_, _) {});
    controller = container.read(keywordResultsProvider(key).notifier);
  });

  test(
    'construction does not read defaults; late startup defaults filter fast results',
    () async {
      expect(defaults.reads, isEmpty);
      final load = controller.loadDefaults();
      final hd = keywordTorrent('Result.1080p');
      controller.present([hd, keywordTorrent('Result.2160p')]);
      defaults.reads.single.complete(configured);
      expect(await load, isTrue);
      expect(subscription.read().results, [hd]);
      expect(subscription.read().filters, same(configured));
      expect(defaults.reads, hasLength(1));
    },
  );

  test('a nonempty choice made during the read wins', () async {
    final load = controller.loadDefaults();
    final chosen = TorrentFilterState(languages: {AudioLanguage.hindi});
    controller.setFilters(chosen);
    defaults.reads.single.complete(configured);
    expect(await load, isFalse);
    expect(subscription.read().filters, same(chosen));
  });

  test('an empty saved default leaves current state alone', () async {
    final before = subscription.read();
    final load = controller.loadDefaults();
    defaults.reads.single.complete(const TorrentFilterState.empty());
    expect(await load, isFalse);
    expect(subscription.read(), same(before));
  });

  test('replaced startup read cannot publish before the newer one', () async {
    final old = controller.loadDefaults();
    final latest = controller.loadDefaults();
    defaults.reads.first.complete(configured);
    expect(await old, isFalse);
    expect(subscription.read().filters.isEmpty, isTrue);
    final chosen = TorrentFilterState(sizes: {SizeBucket.gb4to6});
    defaults.reads.last.complete(chosen);
    expect(await latest, isTrue);
    expect(subscription.read().filters, same(chosen));
  });

  test('read failure is nonfatal and not retried', () async {
    final load = controller.loadDefaults();
    defaults.reads.single.completeError(FormatException('invalid fixture'));
    expect(await load, isFalse);
    expect(subscription.read().filters.isEmpty, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(defaults.reads, hasLength(1));
  });

  test('retired initial action performs no preference read', () async {
    defaults.isCurrent = false;
    expect(await controller.loadDefaults(), isFalse);
    expect(defaults.reads, isEmpty);
  });

  for (final retire in ['profile', 'dispose', 'dependency']) {
    test('$retire rejects a delayed preference result', () async {
      final load = controller.loadDefaults();
      final old = defaults.reads.single;
      if (retire == 'profile') {
        defaults.isCurrent = false;
      } else if (retire == 'dispose') {
        container.dispose();
      } else {
        defaults = FakeKeywordDefaultsRepository();
        container.invalidate(keywordDefaultsRepositoryProvider(key));
        expect(subscription.read().filters.isEmpty, isTrue);
      }
      old.complete(configured);
      expect(await load, isFalse);
      if (retire != 'dispose') {
        expect(subscription.read().filters.isEmpty, isTrue);
      }
    });
  }
}
