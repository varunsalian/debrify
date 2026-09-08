import 'dart:async';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'invalidated preference read completes without an unhandled error',
    () async {
      final pending = Completer<MetadataPreferences>();
      final result = MetadataPreferencesService.loadForBackground(
        isCurrent: () => true,
        read: () => pending.future,
      );
      pending.completeError(
        StateError('Profile changed while loading metadata preferences'),
      );
      expect(await result, isNull);
    },
  );

  test('stale caller discards a successful late policy read', () async {
    final pending = Completer<MetadataPreferences>();
    var current = true;
    final result = MetadataPreferencesService.loadForBackground(
      isCurrent: () => current,
      read: () => pending.future,
    );
    current = false;
    pending.complete(MetadataPreferences());
    expect(await result, isNull);
  });

  test('departed caller does not start a preference read', () async {
    var reads = 0;
    expect(
      await MetadataPreferencesService.loadForBackground(
        isCurrent: () => false,
        read: () async {
          reads++;
          return MetadataPreferences();
        },
      ),
      isNull,
    );
    expect(reads, 0);
  });

  test(
    'failed attempt does not prevent the next current request succeeding',
    () async {
      expect(
        await MetadataPreferencesService.loadForBackground(
          isCurrent: () => true,
          read: () => throw StateError('Storage unavailable'),
        ),
        isNull,
      );
      final preferences = MetadataPreferences(
        providers: {MetadataCategory.trailers: MetadataPreferences.tmdb},
      );
      expect(
        await MetadataPreferencesService.loadForBackground(
          isCurrent: () => true,
          read: () async => preferences,
        ),
        same(preferences),
      );
    },
  );
}
