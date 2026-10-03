import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

typedef DebridDormantSeasonsListDeps = ({
  BuildContext Function() context,
  Widget Function({
    required String fileName,
    required int fileSize,
    required bool isVideo,
    required bool isAdded,
    required bool isSelected,
    required bool isUnrestricting,
    required bool showPlayButtons,
    required VoidCallback onPlay,
    required VoidCallback onAddToPlaylist,
    required VoidCallback onDownload,
    required VoidCallback onCopy,
    required VoidCallback onSelect,
    required int index,
    required Color surface,
    String? episodeInfo,
  })
  buildModernFileCard,
  Future<void> Function(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
    Map<int, bool> unrestrictingFiles,
  )
  playFileOnDemand,
  Future<void> Function(RDTorrent torrent, int index, StateSetter setLocal)
  addFileToPlaylist,
  Future<void> Function(
    RDTorrent torrent,
    int index,
    String fileName,
    StateSetter setLocal,
    Set<int> added,
    Map<int, bool> unrestrictingFiles,
  )
  downloadFileOnDemand,
  Future<void> Function(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
    Map<int, bool> unrestrictingFiles,
  )
  copyFileLinkOnDemand,
});

class DebridDormantSeasonsList {
  DebridDormantSeasonsList(this._deps);
  final DebridDormantSeasonsListDeps _deps;

  Widget buildSeasonsList({
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
  }) {
    // Hoisted out of the itemBuilders below: one theme lookup per list build.
    final app = AppThemeScope.of(_deps.context());
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      shrinkWrap: true,
      itemCount: sortedSeasons.length,
      itemBuilder: (context, seasonIndex) {
        final seasonNumber = sortedSeasons[seasonIndex];
        final seasonFiles = seasonMap[seasonNumber]!;

        // Sort episodes within season
        seasonFiles.sort((a, b) {
          final aEpisode = a['seriesInfo'].episode ?? 0;
          final bEpisode = b['seriesInfo'].episode ?? 0;
          return aEpisode.compareTo(bEpisode);
        });

        // Check if all episodes in this season are selected
        final seasonFileIndices = seasonFiles
            .map((f) => f['index'] as int)
            .toList();
        final allSelected = seasonFileIndices.every(
          (index) => selectedFiles.contains(index),
        );
        final someSelected = seasonFileIndices.any(
          (index) => selectedFiles.contains(index),
        );

        return Container(
          key: ValueKey('season-$seasonNumber'),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: app.cloud.dialogSurface.withValues(alpha: 0.3),
            borderRadius: app.shape.br(12),
            border: Border.all(
              color: const Color(0xFF475569).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: GestureDetector(
            onTap: () {
              setBrowserState(() {
                onSeasonChanged(seasonNumber);
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Season checkbox
                  GestureDetector(
                    onTap: () {
                      setLocal(() {
                        final seasonFileIndices = seasonFiles
                            .map((f) => f['index'] as int)
                            .toList();
                        if (allSelected) {
                          // Deselect all episodes in this season
                          selectedFiles.removeAll(seasonFileIndices);
                        } else {
                          // Select all episodes in this season
                          selectedFiles.addAll(seasonFileIndices);
                        }
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: allSelected
                            ? const Color(0xFF10B981)
                            : someSelected
                            ? const Color(0xFF10B981).withValues(alpha: 0.3)
                            : Colors.transparent,
                        border: Border.all(
                          color: allSelected || someSelected
                              ? const Color(0xFF10B981)
                              : Colors.grey[600]!,
                          width: 2,
                        ),
                        borderRadius: app.shape.br(6),
                      ),
                      // Both glyphs pinned with the green fill/border above.
                      child: allSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : someSelected
                          ? const Icon(
                              Icons.remove,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Folder icon
                  Icon(
                    Icons.folder_rounded,
                    color: const Color(0xFF6366F1),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  // Season title
                  Expanded(
                    child: Text(
                      'Season $seasonNumber',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Episode count
                  Text(
                    '${seasonFiles.length} episodes',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  // Navigation arrow
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.grey[400],
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildEpisodesList({
    required List<Map<String, dynamic>> seasonFiles,
    required Set<int> selectedFiles,
    required Set<int> added,
    required Map<int, bool> unrestrictingFiles,
    required bool showPlayButtons,
    required RDTorrent torrent,
    required StateSetter setLocal,
  }) {
    // Hoisted out of itemBuilder: one theme lookup per list build, not per row.
    final app = AppThemeScope.of(_deps.context());
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      shrinkWrap: true,
      itemCount: seasonFiles.length,
      itemBuilder: (context, index) {
        final seasonFile = seasonFiles[index];
        final file = seasonFile['file'] as Map<String, dynamic>;
        final seriesInfo = seasonFile['seriesInfo'] as SeriesInfo;
        final fileIndex = seasonFile['index'] as int;

        String fileName = file['path']?.toString() ?? 'Unknown file';
        if (fileName.startsWith('/')) {
          fileName = fileName.split('/').last;
        }
        final fileSize = (file['bytes'] ?? 0) as int;
        final isVideo = FileUtils.isVideoFile(fileName);
        final isAdded = added.contains(fileIndex);
        final isSelected = selectedFiles.contains(fileIndex);
        final isUnrestricting = unrestrictingFiles[fileIndex] ?? false;

        return Container(
          key: ValueKey('file-$fileIndex'),
          margin: const EdgeInsets.only(bottom: 12),
          child: _deps.buildModernFileCard(
            fileName: fileName,
            fileSize: fileSize,
            isVideo: isVideo,
            isAdded: isAdded,
            isSelected: isSelected,
            isUnrestricting: isUnrestricting,
            showPlayButtons: showPlayButtons,
            surface: app.cloud.dialogSurface,
            onPlay: () => _deps.playFileOnDemand(
              torrent,
              fileIndex,
              setLocal,
              unrestrictingFiles,
            ),
            onAddToPlaylist: () =>
                _deps.addFileToPlaylist(torrent, fileIndex, setLocal),
            onDownload: () => _deps.downloadFileOnDemand(
              torrent,
              fileIndex,
              fileName,
              setLocal,
              added,
              unrestrictingFiles,
            ),
            onCopy: () => _deps.copyFileLinkOnDemand(
              torrent,
              fileIndex,
              setLocal,
              unrestrictingFiles,
            ),
            onSelect: () {
              setLocal(() {
                if (isSelected) {
                  selectedFiles.remove(fileIndex);
                } else {
                  selectedFiles.add(fileIndex);
                }
              });
            },
            index: index,
            episodeInfo: seriesInfo.episode != null
                ? 'E${seriesInfo.episode.toString().padLeft(2, '0')}'
                : null,
          ),
        );
      },
    );
  }
}
