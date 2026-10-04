import 'package:debrify/models/series_playlist.dart';

class PlaylistContentSeriesState {
  // Progress tracking cache
  Map<String, Map<String, dynamic>> fileProgressCache = {};

  // OTT View state
  SeriesPlaylist? seriesPlaylist;

  int selectedSeasonNumber = 1;

  bool isLoadingSeriesMetadata = false;
}
