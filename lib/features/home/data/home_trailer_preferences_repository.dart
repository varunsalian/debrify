import '../models/home_trailer_preferences.dart';

class HomeTrailerPreferencesRepository {
  const HomeTrailerPreferencesRepository({
    required this.readEnabled,
    required this.readAudioEnabled,
    required this.readVolume,
  });

  final Future<bool> Function() readEnabled;
  final Future<bool> Function(bool useHomeAudio) readAudioEnabled;
  final Future<int> Function(bool useHomeAudio) readVolume;

  Future<HomeTrailerPreferences> read({required bool useHomeAudio}) async {
    // Preserve parallel reads and publication only after all three resolve.
    final values = await Future.wait<Object>([
      readEnabled(),
      readAudioEnabled(useHomeAudio),
      readVolume(useHomeAudio),
    ]);
    return (
      enabled: values[0] as bool,
      volume: (values[1] as bool) ? (values[2] as int).toDouble() : 0.0,
    );
  }
}
