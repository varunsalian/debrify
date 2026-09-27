import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/storage_service.dart';
import '../data/home_trailer_preferences_repository.dart';

final homeTrailerPreferencesRepositoryProvider =
    Provider<HomeTrailerPreferencesRepository>((ref) {
      AmbientTrailerSurface surface(bool useHomeAudio) => useHomeAudio
          ? AmbientTrailerSurface.homeHero
          : AmbientTrailerSurface.detail;
      return HomeTrailerPreferencesRepository(
        readEnabled: StorageService.getHomeHeroTrailerEnabled,
        readAudioEnabled: (home) =>
            StorageService.getAmbientTrailerAudioEnabled(surface(home)),
        readVolume: (home) =>
            StorageService.getAmbientTrailerVolume(surface(home)),
      );
    }, dependencies: const []);
