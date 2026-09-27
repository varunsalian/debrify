import 'package:debrify/core/metadata/metadata_presentation_cache.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MetadataPresentationCache cache;
  late DateTime now;
  final scope = ProfileScope(
    profileId: 'a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final policy = MetadataPreferences(language: 'fr-FR');
  const item = StremioMeta(id: 'same-id', type: 'movie', name: 'Original');
  const result = MetadataPresentation(item);

  setUp(() {
    now = DateTime.utc(2026, 9, 27);
    cache = MetadataPresentationCache(now: () => now);
    cache.prepare(scope: scope, revision: 7, preferences: policy);
  });

  test('equal scope and serialized policy retain entries across readers', () {
    cache.store(item, result);
    cache.prepare(
      scope: ProfileScope(profileId: 'a', dataGeneration: 1, sessionEpoch: 1),
      revision: 7,
      preferences: MetadataPreferences(language: 'fr-FR'),
    );
    expect(cache.peek(item)?.value, same(result));
  });

  for (final next in [
    null,
    ProfileScope(profileId: 'b', dataGeneration: 1, sessionEpoch: 1),
    ProfileScope(profileId: 'a', dataGeneration: 2, sessionEpoch: 1),
    ProfileScope(profileId: 'a', dataGeneration: 1, sessionEpoch: 2),
  ]) {
    test(
      'scope ${next?.cacheKey ?? 'legacy'} invalidates the previous cache',
      () {
        cache.store(item, result);
        cache.prepare(scope: next, revision: 7, preferences: policy);
        expect(cache.take(item), isNull);
      },
    );
  }

  for (final revisionChange in [false, true]) {
    test(
      '${revisionChange ? 'revision' : 'policy'} change invalidates an unchanged profile',
      () {
        cache.store(item, result);
        cache.prepare(
          scope: scope,
          revision: revisionChange ? 8 : 7,
          preferences: revisionChange
              ? policy
              : MetadataPreferences(language: 'de-DE'),
        );
        expect(cache.take(item), isNull);
      },
    );
  }

  test(
    'keys retain catalog object identity; visible reads consume while preload reads do not',
    () {
      final equivalent = StremioMeta(
        id: item.id,
        type: item.type,
        name: item.name,
      );
      cache.store(item, result);
      expect(cache.peek(equivalent), isNull);
      expect(cache.peek(item)?.value, same(result));
      expect(cache.peek(item)?.value, same(result));
      expect(cache.take(item)?.value, same(result));
      expect(cache.peek(item), isNull);
      expect(cache.take(item), isNull);
    },
  );

  test(
    'only complete non-retryable presentations enter or replace the cache',
    () {
      for (final incomplete in [
        const MetadataPresentation(item, retryable: true),
        const MetadataPresentation(
          item,
          unavailable: {MetadataCategory.posters},
        ),
      ]) {
        cache.store(item, incomplete);
        expect(cache.peek(item), isNull);
      }
      cache.store(item, result);
      cache.store(item, const MetadataPresentation(item, retryable: true));
      cache.store(
        item,
        const MetadataPresentation(
          item,
          unavailable: {MetadataCategory.posters},
        ),
      );
      expect(cache.take(item)?.value, same(result));
    },
  );

  test(
    'entries expose the original 15-minute expiry for consumer freshness checks',
    () {
      cache.store(item, result);
      final entry = cache.peek(item)!;
      expect(entry.expires, now.add(const Duration(minutes: 15)));
      now = now.add(const Duration(minutes: 15));
      expect(entry.expires.isAfter(now), isFalse);
      // The visible consumer removes even an expired record before resolving.
      expect(cache.take(item), entry);
      expect(cache.peek(item), isNull);
      cache.store(item, result);
      expect(cache.peek(item)!.expires, now.add(const Duration(minutes: 15)));
    },
  );

  test(
    'the 256-entry bound preserves preload FIFO and visible-read promotion',
    () {
      final items = List.generate(
        258,
        (i) => StremioMeta(id: '$i', type: 'movie', name: '$i'),
      );
      for (final item in items.take(256)) {
        cache.store(item, MetadataPresentation(item));
      }
      expect(cache.peek(items[0]), isNotNull);
      final promoted = cache.take(items[1])!;
      cache.store(items[1], promoted.value);
      cache.store(items[256], MetadataPresentation(items[256]));
      expect(cache.peek(items[0]), isNull);
      expect(cache.peek(items[1]), isNotNull);
      cache.store(items[257], MetadataPresentation(items[257]));
      expect(cache.peek(items[2]), isNull);
      expect(cache.peek(items[1]), isNotNull);
      expect(items.where((item) => cache.peek(item) != null), hasLength(256));
    },
  );

  test(
    'preload replacement refreshes expiry without promoting insertion order',
    () {
      final items = List.generate(
        257,
        (i) => StremioMeta(id: '$i', type: 'movie', name: '$i'),
      );
      for (final item in items.take(256)) {
        cache.store(item, MetadataPresentation(item));
      }
      now = now.add(const Duration(minutes: 2));
      cache.store(items.first, MetadataPresentation(items.first));
      expect(
        cache.peek(items.first)!.expires,
        now.add(const Duration(minutes: 15)),
      );
      cache.store(items.last, MetadataPresentation(items.last));
      expect(cache.peek(items.first), isNull);
      expect(cache.peek(items[1]), isNotNull);
    },
  );
}
