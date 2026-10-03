import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

typedef DebridDormantSeriesBrowserDeps = ({
  BuildContext Function() context,
  Widget Function({
    required Map<int, List<Map<String, dynamic>>> seasonMap,
    required List<int> sortedSeasons,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
    required StateSetter setBrowserState,
    required Function(int?) onSeasonChanged,
  })
  buildSeasonsList,
  Widget Function({
    required List<Map<String, dynamic>> seasonFiles,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
  })
  buildEpisodesList,
});

class DebridDormantSeriesBrowser {
  DebridDormantSeriesBrowser(this._deps);
  final DebridDormantSeriesBrowserDeps _deps;

  Widget _buildSeriesFileBrowser({
    required List<dynamic> files,
    required List<SeriesInfo> seriesInfos,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
  }) {
    // Track current season for navigation
    int? _currentSeason;

    return StatefulBuilder(
      builder: (context, setBrowserState) {
        return buildFileBrowserContent(
          files: files,
          seriesInfos: seriesInfos,
          selectedFiles: selectedFiles,
          added: added,
          unrestrictingFiles: unrestrictingFiles,
          showPlayButtons: showPlayButtons,
          torrent: torrent,
          setLocal: setLocal,
          setBrowserState: setBrowserState,
          currentSeason: _currentSeason,
          onSeasonChanged: (season) {
            setBrowserState(() {
              _currentSeason = season;
            });
          },
        );
      },
    );
  }

  Widget buildFileBrowserContent({
    required List<dynamic> files,
    required List<SeriesInfo> seriesInfos,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
    required StateSetter setBrowserState,
    required int? currentSeason,
    required Function(int?) onSeasonChanged,
  }) {
    final app = AppThemeScope.of(_deps.context());
    // Use the passed currentSeason instead of defining a local one
    final _currentSeason = currentSeason;
    // Group files by season
    final seasonMap = <int, List<Map<String, dynamic>>>{};
    String? seriesTitle;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final seriesInfo = seriesInfos[i];

      if (seriesInfo.isSeries && seriesInfo.season != null) {
        final seasonNumber = seriesInfo.season!;
        seriesTitle ??= seriesInfo.title;

        seasonMap.putIfAbsent(seasonNumber, () => []);
        seasonMap[seasonNumber]!.add({
          'file': file,
          'seriesInfo': seriesInfo,
          'index': i,
        });
      }
    }

    // Sort seasons
    final sortedSeasons = seasonMap.keys.toList()..sort();

    return Column(
      children: [
        // Breadcrumb navigation
        if (_currentSeason != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: app.cloud.dialogSurface.withValues(alpha: 0.5),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF475569).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setBrowserState(() {
                      onSeasonChanged(null);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: app.shape.br(8),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_back_rounded,
                          color: Color(0xFF6366F1),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Back to Seasons',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Season $_currentSeason',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Selection counter
                if (selectedFiles.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: app.shape.br(12),
                    ),
                    child: Text(
                      // Ink pinned with the green fill above: the surface does
                      // not follow the palette, so its ink must not either.
                      '${selectedFiles.length} selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Content area
        Expanded(
          child: _currentSeason == null
              ? _deps.buildSeasonsList(
                  seasonMap: seasonMap,
                  sortedSeasons: sortedSeasons,
                  selectedFiles: selectedFiles,
                  added: added,
                  unrestrictingFiles: unrestrictingFiles,
                  showPlayButtons: showPlayButtons,
                  torrent: torrent,
                  setLocal: setLocal,
                  setBrowserState: setBrowserState,
                  onSeasonChanged: onSeasonChanged,
                )
              : _deps.buildEpisodesList(
                  seasonFiles: seasonMap[_currentSeason]!,
                  selectedFiles: selectedFiles,
                  added: added,
                  unrestrictingFiles: unrestrictingFiles,
                  showPlayButtons: showPlayButtons,
                  torrent: torrent,
                  setLocal: setLocal,
                ),
        ),
      ],
    );
  }
}
