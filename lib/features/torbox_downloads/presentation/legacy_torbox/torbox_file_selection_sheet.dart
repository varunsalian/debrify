import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
import 'package:debrify/features/torbox_downloads/presentation/maybe_blur.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

typedef TorboxFileSelectionSheetDeps = ({
  void Function(String action) showComingSoon,
  BuildContext Function() context,
  Widget Function({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  })
  buildTorboxRawList,
  Future<void> Function(TorboxTorrent torrent, TorboxFile file)
  copyTorboxFileLink,
  Widget Function({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required int? currentSeason,
    required ValueChanged<int?> onSeasonChange,
    required ValueChanged<int> onToggleFile,
    required void Function(int season, List<int> indices) onToggleSeason,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  })
  buildTorboxSeriesView,
  Widget Function({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  })
  buildTorboxMovieView,
  Widget Function({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  })
  buildTorboxGenericList,
  Future<bool> Function({
    required TorboxTorrent torrent,
    required List<TorboxFileEntry> entriesToDownload,
    required BuildContext sheetContext,
  })
  enqueueTorboxDownloads,
});

class TorboxFileSelectionSheet {
  TorboxFileSelectionSheet(this._deps);
  final TorboxFileSelectionSheetDeps _deps;

  Future<void> showTorboxFileSelectionSheet(TorboxTorrent torrent) async {
    if (torrent.files.isEmpty) {
      _deps.showComingSoon('No files available');
      return;
    }

    final files = torrent.files;
    final filenames = files
        .map(
          (file) => file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name),
        )
        .toList();
    final seriesInfos = SeriesParser.parsePlaylist(filenames);

    final entries = List<TorboxFileEntry>.generate(
      files.length,
      (index) => TorboxFileEntry(
        file: files[index],
        index: index,
        seriesInfo: index < seriesInfos.length
            ? seriesInfos[index]
            : SeriesParser.parseFilename(files[index].shortName),
      ),
    );

    final Set<int> selectedIndices = <int>{};

    bool showRaw = false;
    int? currentSeason;
    bool isProcessing = false;
    final bool isSeries = isLikelySeries(entries);
    final bool hasVideo = entries.any(
      (entry) => torboxFileLooksLikeVideo(entry.file),
    );
    final bool isMovieCollection = !isSeries && hasVideo;

    await showDialog<void>(
      context: _deps.context(),
      builder: (sheetContext) {
        final app = AppThemeScope.of(sheetContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: maybeBlur(
            sigma: 8,
            StatefulBuilder(
              builder: (context, setSheetState) {
                final selectedEntries =
                    entries
                        .where((entry) => selectedIndices.contains(entry.index))
                        .toList()
                      ..sort((a, b) => a.index.compareTo(b.index));
                final selectedBytes = selectedEntries.fold<int>(
                  0,
                  (previousValue, entry) => previousValue + entry.file.size,
                );

                Widget content;
                if (showRaw) {
                  content = _deps.buildTorboxRawList(
                    entries: entries,
                    selectedIndices: selectedIndices,
                    onToggle: (index) {
                      setSheetState(() {
                        if (selectedIndices.contains(index)) {
                          selectedIndices.remove(index);
                        } else {
                          selectedIndices.add(index);
                        }
                      });
                    },
                    onCopy: (entry) =>
                        _deps.copyTorboxFileLink(torrent, entry.file),
                  );
                } else if (isSeries) {
                  content = _deps.buildTorboxSeriesView(
                    entries: entries,
                    selectedIndices: selectedIndices,
                    currentSeason: currentSeason,
                    onSeasonChange: (season) {
                      setSheetState(() {
                        currentSeason = season;
                      });
                    },
                    onToggleFile: (index) {
                      setSheetState(() {
                        if (selectedIndices.contains(index)) {
                          selectedIndices.remove(index);
                        } else {
                          selectedIndices.add(index);
                        }
                      });
                    },
                    onToggleSeason: (season, seasonIndices) {
                      setSheetState(() {
                        final hasAll = seasonIndices.every(
                          (index) => selectedIndices.contains(index),
                        );
                        if (hasAll) {
                          for (final idx in seasonIndices) {
                            selectedIndices.remove(idx);
                          }
                        } else {
                          selectedIndices.addAll(seasonIndices);
                        }
                      });
                    },
                    onCopy: (entry) =>
                        _deps.copyTorboxFileLink(torrent, entry.file),
                  );
                } else if (isMovieCollection) {
                  content = _deps.buildTorboxMovieView(
                    entries: entries,
                    selectedIndices: selectedIndices,
                    onToggle: (index) {
                      setSheetState(() {
                        if (selectedIndices.contains(index)) {
                          selectedIndices.remove(index);
                        } else {
                          selectedIndices.add(index);
                        }
                      });
                    },
                    onCopy: (entry) =>
                        _deps.copyTorboxFileLink(torrent, entry.file),
                  );
                } else {
                  content = _deps.buildTorboxGenericList(
                    entries: entries,
                    selectedIndices: selectedIndices,
                    onToggle: (index) {
                      setSheetState(() {
                        if (selectedIndices.contains(index)) {
                          selectedIndices.remove(index);
                        } else {
                          selectedIndices.add(index);
                        }
                      });
                    },
                    onCopy: (entry) =>
                        _deps.copyTorboxFileLink(torrent, entry.file),
                  );
                }

                final selectedCount = selectedEntries.length;
                final totalCount = entries.length;
                final selectionSummary = totalCount == 0
                    ? 'No files available'
                    : selectedCount == totalCount
                    ? 'All $totalCount files selected'
                    : '$selectedCount of $totalCount files selected';
                final selectedSizeText = selectedCount == 0
                    ? '0 B'
                    : Formatters.formatFileSize(selectedBytes);

                return Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.9,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0F172A).withValues(alpha: 0.98),
                        app.cloud.dialogSurface.withValues(alpha: 0.98),
                      ],
                    ),
                    borderRadius: app.shape.br(28),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: app.cloud.dialogSurface.withValues(alpha: 0.6),
                          borderRadius: app.shape.br(16),
                          border: Border.all(
                            color: const Color(
                              0xFF475569,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectionSummary,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Selected size: $selectedSizeText',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  'Raw',
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch.adaptive(
                                  value: showRaw,
                                  activeColor: const Color(0xFF6366F1),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      showRaw = value;
                                      currentSeason = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: content),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: const Color(
                                0xFF1F2937,
                              ).withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: isProcessing
                                        ? null
                                        : () async {
                                            setSheetState(
                                              () => isProcessing = true,
                                            );
                                            final closed = await _deps
                                                .enqueueTorboxDownloads(
                                                  torrent: torrent,
                                                  entriesToDownload: entries,
                                                  sheetContext: sheetContext,
                                                );
                                            if (!closed) {
                                              setSheetState(
                                                () => isProcessing = false,
                                              );
                                            }
                                          },
                                    icon: const Icon(Icons.download_rounded),
                                    label: Text(
                                      isProcessing
                                          ? 'Preparing…'
                                          : 'Download All',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.2),
                                      foregroundColor: const Color(0xFF10B981),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: app.shape.br(16),
                                      ),
                                    ),
                                  ),
                                ),
                                if (selectedEntries.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: isProcessing
                                          ? null
                                          : () async {
                                              setSheetState(
                                                () => isProcessing = true,
                                              );
                                              final closed = await _deps
                                                  .enqueueTorboxDownloads(
                                                    torrent: torrent,
                                                    entriesToDownload:
                                                        selectedEntries,
                                                    sheetContext: sheetContext,
                                                  );
                                              if (!closed) {
                                                setSheetState(
                                                  () => isProcessing = false,
                                                );
                                              }
                                            },
                                      icon: const Icon(Icons.checklist_rounded),
                                      label: Text(
                                        isProcessing
                                            ? 'Preparing…'
                                            : 'Download Selected',
                                      ),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: app.shape.br(16),
                                  ),
                                ),
                                child: const Text(
                                  'Close',
                                  style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
