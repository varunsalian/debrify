import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/services/collection_native_source_service.dart';

/// Opt-in read-only integration check:
/// flutter test --dart-define-from-file=.env.local.json
///   --dart-define=COLLECTION_LIVE_TESTS=true test/collection_native_live_test.dart
void main() {
  const enabled = bool.fromEnvironment('COLLECTION_LIVE_TESTS');
  final service = CollectionNativeSourceService(
    resolveIds: !const bool.fromEnvironment('COLLECTION_NO_ENRICHMENT'),
    tmdbClientFactory: const bool.fromEnvironment('COLLECTION_STOCK_TRANSPORT')
        ? http.Client.new
        : null,
  );
  tearDownAll(service.close);
  test(
    'live Kaptain previews cold and cached',
    () async {
      final pack = HomeCollectionParser.parse(
        utf8.decode(
          gzip.decode(
            File(
              'test/fixtures/collections/kaptain-native-0.61.json.gz',
            ).readAsBytesSync(),
          ),
        ),
      );
      final groups = <String, List<CollectionCatalogSource>>{};
      for (final source
          in pack.expand((c) => c.folders).expand((f) => f.sources)) {
        if (source.provider == 'tmdb') {
          (groups[source.tmdbSourceType!] ??= []).add(source);
        }
      }
      final sample = <CollectionCatalogSource>[];
      for (var index = 0; sample.length < 48; index++) {
        for (final group in groups.values) {
          if (index < group.length && sample.length < 48) {
            sample.add(group[index]);
          }
        }
      }
      for (final concurrency in [4, 12]) {
        var next = 0;
        final times = <int>[];
        var failures = 0;
        Future<void> worker() async {
          while (next < sample.length) {
            final source = sample[next++];
            final watch = Stopwatch()..start();
            try {
              final page = await service.fetchPreview(source, 1);
              expect(
                page.items.every((m) => m.id.isNotEmpty && m.name.isNotEmpty),
                isTrue,
              );
            } catch (error, stack) {
              failures++;
              debugPrint(
                'Kaptain source failed: ${source.tmdbSourceType}: ${error.runtimeType}',
              );
              debugPrint('$error\n$stack');
            }
            times.add(watch.elapsedMilliseconds);
          }
        }

        await Future.wait(List.generate(concurrency, (_) => worker()));
        times.sort();
        debugPrint(
          'Kaptain concurrency=$concurrency sources=${sample.length} failures=$failures median_ms=${times[times.length ~/ 2]} max_ms=${times.last}',
        );
        expect(failures, 0);
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 5)),
  );
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
