import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/services/collection_native_source_service.dart';

/// Opt-in read-only integration check:
/// flutter test --dart-define-from-file=.env.local.json
///   --dart-define=COLLECTION_LIVE_TESTS=true test/collection_native_live_test.dart
void main() {
  const enabled = bool.fromEnvironment('COLLECTION_LIVE_TESTS');
  final service = CollectionNativeSourceService();
  tearDownAll(service.close);
  for (final entry in {
    'DISCOVER': null,
    'LIST': 1,
    'COLLECTION': 14890,
    'COMPANY': 420,
    'NETWORK': 213,
    'PERSON': 287,
    'DIRECTOR': 525,
  }.entries) {
    test(
      'live TMDB ${entry.key} returns browsable titles',
      () async {
        final source = CollectionCatalogSource.fromJson({
          'provider': 'tmdb',
          'tmdbSourceType': entry.key,
          'tmdbId': entry.value,
        })!;
        final page = await service.fetch(source, 1);
        expect(page.items, isNotEmpty);
        expect(
          page.items.every((m) => m.name.isNotEmpty && m.id.isNotEmpty),
          true,
        );
        expect(page.items.any((m) => m.imdbId != null), true);
      },
      skip: !enabled,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  test(
    'live public Trakt collection returns titles',
    () async {
      final page = await service.fetch(
        CollectionCatalogSource.fromJson({
          'provider': 'trakt',
          'traktListId': 1248149,
          'mediaType': 'MOVIE',
          'sortBy': 'rank',
          'sortHow': 'asc',
        })!,
        1,
      );
      expect(page.items, isNotEmpty);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
