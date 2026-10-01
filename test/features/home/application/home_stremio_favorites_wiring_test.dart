import 'dart:convert';
import 'package:debrify/features/home/application/home_saved_content_providers.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/stremio_tv_service.dart' as shared;
import 'package:debrify/screens/stremio_tv/stremio_tv_service.dart' as legacy;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default adapter reads actual favourites, local discovery and rotations',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': '[]',
        'stremio_tv_favorite_channels_v1': jsonEncode({
          'local:mine:movie': true,
        }),
        'stremio_tv_rotation_minutes': 120,
        'stremio_tv_series_rotation_minutes': 30,
        'stremio_tv_local_catalogs_v1': jsonEncode([
          {
            'id': 'mine',
            'name': 'Mine',
            'type': 'movie',
            'items': [
              {
                'id': 'tt123',
                'name': 'Film',
                'poster': 'https://example.test/poster',
              },
            ],
          },
          {
            'id': 'other',
            'name': 'Other',
            'type': 'movie',
            'items': [
              {'id': 'tt456', 'name': 'Other film'},
            ],
          },
        ]),
      });
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      expect(
        legacy.StremioTvService.instance,
        same(shared.StremioTvService.instance),
      );
      final container = ProviderContainer.test();
      final repository = container.read(homeStremioFavoritesRepositoryProvider);
      final read = (await repository.read(isCurrent: () => true))!;
      expect(read.hasFavoriteIds, isTrue);
      expect(read.favorites.rotationMinutes, 120);
      expect(read.favorites.seriesRotationMinutes, 30);
      final favorite = read.favorites.channels.single;
      expect(favorite.id, 'local:mine:movie');
      expect(favorite.displayName, 'Local: Mine');
      expect(favorite.type, 'movie');
      expect(favorite.items.single.id, 'tt123');
      expect(favorite.items.single.poster, 'https://example.test/poster');
    },
  );
}
