class StremioTvSettingsState {
  int rotationMinutes = 90;

  int seriesRotationMinutes = 45;

  bool randomEpisodes = false;

  bool autoRefresh = true;

  String preferredQuality = 'auto';

  String debridProvider = 'auto';

  bool rdSkipBlockedTorrents = false;

  bool torrentsFirst = true;

  List<MapEntry<String, String>> availableProviders = [];
  // -1 = no limit (slot progress), 0 = beginning
  int maxStartPercent = -1;

  bool hideNowPlaying = false;
  // Whether MDBList is connected — gates the "Import → From MDBList" entry so
  // an unauthed user isn't offered a dead import (MDBList is also hidden from
  // Settings for the alpha).
  bool mdblistConnected = false;
}
