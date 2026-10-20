import 'dart:async';

import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:debrify/services/storage/playlist_artwork_storage.dart';
import 'package:debrify/services/storage/playlist_metadata_storage.dart';
import 'package:debrify/utils/movie_parser.dart';
import 'package:flutter/material.dart';

abstract interface class VpMetadataPreloadHost {
  int get currentIndex;
  String get dynamicTitle;
  int get playlistIdentityToken;
  SeriesPlaylist? get seriesPlaylist;
  bool get singleFileImdbFetched;
  set singleFileImdbFetched(bool v);
  set singleFileImdbId(String? v);
  bool get trackPreferencesReadyForAddonSubtitles;
  Map<String, dynamic>? constructPlaylistItemData();
  bool get mounted;
  void setState(VoidCallback fn);
  String? get contentImdbId;
  String get title;
  String? get rdTorrentId;
  String? get torboxTorrentId;
  String? get pikpakCollectionId;
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle();
}

class VpMetadataPreload {
  VpMetadataPreload(this._host);
  final VpMetadataPreloadHost _host;

  /// Preload episode information in the background
  Future<void> preloadEpisodeInfo() async {
    final seriesPlaylist = _host.seriesPlaylist;

    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlistIdentityToken = _host.playlistIdentityToken;
      // Preload episode information in the background
      // Pass IMDB ID from catalog for faster, more accurate lookup
      await seriesPlaylist
          .fetchEpisodeInfo(
            playlistItem: _host.constructPlaylistItemData(),
            imdbId: _host.contentImdbId,
          )
          .then((_) async {
            if (!_host.mounted ||
                playlistIdentityToken != _host.playlistIdentityToken ||
                !identical(seriesPlaylist, _host.seriesPlaylist)) {
              return;
            }

            // TVMaze can discover the series IMDB ID after the initial subtitle
            // restore has already run. Retry the existing addon subtitle path so
            // RD/Torbox season packs do not require reopening the player.
            retryAddonSubtitleFetchAfterSeriesMetadata(
              seriesPlaylist,
              playlistIdentityToken,
            );

            // Trigger UI update to show the episode info
            _host.setState(() {});

            // Save discovered IMDB ID back to playlist item for future direct plays
            await saveImdbIdToPlaylist(seriesPlaylist);

            // Extract poster URL from series data and save to playlist
            await saveSeriesPosterToPlaylist(seriesPlaylist);
          })
          .catchError((error) {
            // Silently handle errors - this is just preloading
          });
    } else if (seriesPlaylist != null && !seriesPlaylist.isSeries) {
      // For non-series content (movie collections), fetch movie metadata for current index
      // This enables subtitles for movies from Debrid/Torbox/PikPak
      await seriesPlaylist
          .fetchMovieMetadataForIndex(_host.currentIndex)
          .then((imdbId) {
            // Trigger UI update if IMDB ID was discovered
            if (_host.mounted && imdbId != null) {
              _host.setState(() {});
            }
          })
          .catchError((error) {
            // Silently handle errors - this is just preloading
          });
    } else if (seriesPlaylist == null && _host.contentImdbId == null) {
      // Single-file playback (no playlist) - try to fetch movie metadata from title
      await fetchSingleFileMovieMetadata();
    }
  }

  void retryAddonSubtitleFetchAfterSeriesMetadata(
    SeriesPlaylist seriesPlaylist,
    int playlistIdentityToken,
  ) {
    final imdbId = seriesPlaylist.imdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) return;
    if (playlistIdentityToken != _host.playlistIdentityToken) return;
    if (!identical(seriesPlaylist, _host.seriesPlaylist)) return;

    // If track preferences have not completed yet, the normal restore path will
    // see the newly discovered IMDB ID and fetch subtitles at the right time.
    if (!_host.trackPreferencesReadyForAddonSubtitles) {
      debugPrint(
        'VideoPlayer: Series IMDB resolved before track restore; subtitle fetch will run during restore',
      );
      return;
    }

    debugPrint(
      'VideoPlayer: Series IMDB resolved after initial subtitle fetch, retrying addon subtitles (IMDB: $imdbId)',
    );
    unawaited(_host.fetchAndMaybeAutoSelectAddonSubtitle());
  }

  /// Fetch movie metadata for single-file playback (when no playlist exists)
  Future<void> fetchSingleFileMovieMetadata() async {
    // Skip if already fetched or we have an IMDB ID
    if (_host.singleFileImdbFetched || _host.contentImdbId != null) {
      return;
    }

    _host.singleFileImdbFetched = true;

    // Use dynamic title (updated on stream switch) or fall back to widget title
    final title = _host.dynamicTitle.isNotEmpty
        ? _host.dynamicTitle
        : _host.title;
    if (title.isEmpty) {
      debugPrint('MovieMetadata: No title for single-file lookup');
      return;
    }

    debugPrint('MovieMetadata: Single-file lookup for "$title"');

    // Parse the title for movie info
    final movieInfo = MovieParser.parseFilename(title);

    if (!movieInfo.hasYear) {
      debugPrint('MovieMetadata: No year pattern in single-file title');
      return;
    }

    if (movieInfo.title == null || movieInfo.title!.isEmpty) {
      debugPrint('MovieMetadata: Could not extract title from single-file');
      return;
    }

    debugPrint(
      'MovieMetadata: Parsed single-file title="${movieInfo.title}", year=${movieInfo.year}',
    );

    try {
      final metadata = await MovieMetadataService.lookupMovie(
        movieInfo.title!,
        movieInfo.year,
      );

      if (metadata != null) {
        _host.singleFileImdbId = metadata.imdbId;
        debugPrint(
          'MovieMetadata: Found IMDB ID "${metadata.imdbId}" for single-file "${metadata.title}"',
        );
        if (_host.mounted) {
          _host.setState(() {});
        }
      } else {
        debugPrint('MovieMetadata: No match found for single-file');
      }
    } catch (e) {
      debugPrint('MovieMetadata: Error during single-file lookup: $e');
    }
  }

  Future<void> saveImdbIdToPlaylist(SeriesPlaylist seriesPlaylist) async {
    final imdbId = seriesPlaylist.imdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) return;
    if (_host.contentImdbId != null) return;

    await PlaylistMetadataStorage.updatePlaylistItemImdbId(
      imdbId,
      rdTorrentId: _host.rdTorrentId,
      torboxTorrentId: _host.torboxTorrentId,
      pikpakCollectionId: _host.pikpakCollectionId,
    );
  }

  /// Save series poster URL to playlist item
  Future<void> saveSeriesPosterToPlaylist(SeriesPlaylist seriesPlaylist) async {
    print('🎬 _saveSeriesPosterToPlaylist called');
    print('  seriesTitle: ${seriesPlaylist.seriesTitle}');

    if (seriesPlaylist.seriesTitle == null) {
      print('  ⚠️ No series title, skipping poster save');
      return;
    }

    // Get identifiers from widget parameters
    final rdTorrentId = _host.rdTorrentId;
    final torboxTorrentId = _host.torboxTorrentId;
    final pikpakCollectionId = _host.pikpakCollectionId;

    print('  rdTorrentId: $rdTorrentId');
    print('  torboxTorrentId: $torboxTorrentId');
    print('  pikpakCollectionId: $pikpakCollectionId');

    // Need at least one identifier to save poster
    if ((rdTorrentId == null || rdTorrentId.isEmpty) &&
        (torboxTorrentId == null || torboxTorrentId.isEmpty) &&
        (pikpakCollectionId == null || pikpakCollectionId.isEmpty)) {
      print('  ⚠️ No valid identifier found, skipping poster save');
      return;
    }

    final posterUrl = seriesPlaylist.showPosterUrl;
    if (posterUrl == null || posterUrl.isEmpty) {
      print('  ⚠️ No poster URL from fetchEpisodeInfo');
      return;
    }

    print('  Poster URL: $posterUrl');
    try {
      if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          pikpakCollectionId: pikpakCollectionId,
        );
      }
    } catch (e) {
      print('  ❌ Error saving poster: $e');
    }
  }
}
