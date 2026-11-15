import 'package:debrify/features/discover/models/discover_source_state.dart';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/storage/discover_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each media-server source browses its own server kind', () {
    expect(
      DiscoverSources.mediaServerKind(DiscoverSources.jellyfin),
      MediaServerKind.jellyfin,
    );
    expect(
      DiscoverSources.mediaServerKind(DiscoverSources.emby),
      MediaServerKind.emby,
    );
    expect(
      DiscoverSources.mediaServerKind(DiscoverSources.plex),
      MediaServerKind.plex,
    );
    for (final other in [
      DiscoverSources.cw,
      DiscoverSources.trakt,
      DiscoverSources.tmdb,
      '${DiscoverSources.addonPrefix}x',
    ]) {
      expect(DiscoverSources.mediaServerKind(other), isNull, reason: other);
    }
  });

  test('Plex can be the source Discover opens with', () async {
    SharedPreferences.setMockInitialValues({});
    await DiscoverStorage.setDiscoverDefaultSource(DiscoverSources.plex);
    expect(await DiscoverStorage.getDiscoverDefaultSource(), 'plex');
  });
}
