import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef TorboxSeriesLayoutDeps = ({
  BuildContext Function() context,
  Widget Function(String title) buildSectionHeader,
  Widget Function({
    required TorboxFileEntry entry,
    required bool isSelected,
    required VoidCallback onToggle,
    required int animationIndex,
    required Color surface,
    String? badge,
    String? subtitle,
    Future<void> Function()? onCopy,
  })
  buildTorboxFileCard,
});

class TorboxSeriesLayout {
  TorboxSeriesLayout(this._deps);
  final TorboxSeriesLayoutDeps _deps;

  Widget buildTorboxSeriesView({
    required List<TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required int? currentSeason,
    required ValueChanged<int?> onSeasonChange,
    required ValueChanged<int> onToggleFile,
    required void Function(int season, List<int> indices) onToggleSeason,
    Future<void> Function(TorboxFileEntry entry)? onCopy,
  }) {
    final app = AppThemeScope.of(_deps.context());
    final seasonMap = <int, List<TorboxFileEntry>>{};
    final otherEntries = <TorboxFileEntry>[];

    for (final entry in entries) {
      final info = entry.seriesInfo;
      if (info.isSeries && info.season != null && info.episode != null) {
        seasonMap.putIfAbsent(info.season!, () => []).add(entry);
      } else {
        otherEntries.add(entry);
      }
    }

    for (final seasonEntries in seasonMap.values) {
      seasonEntries.sort((a, b) {
        final epA = a.seriesInfo.episode ?? 0;
        final epB = b.seriesInfo.episode ?? 0;
        return epA.compareTo(epB);
      });
    }

    final sortedSeasons = seasonMap.keys.toList()..sort();

    if (currentSeason != null && !seasonMap.containsKey(currentSeason)) {
      onSeasonChange(null);
    }

    if (currentSeason == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          _deps.buildSectionHeader('Seasons'),
          const SizedBox(height: 12),
          for (final seasonNumber in sortedSeasons)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    app.cloud.dialogSurface.withValues(alpha: 0.8),
                    const Color(0xFF111827).withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: app.shape.br(18),
                border: Border.all(
                  color: const Color(0xFF475569).withValues(alpha: 0.3),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: app.shape.br(18),
                  onTap: () => onSeasonChange(seasonNumber),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            onToggleSeason(
                              seasonNumber,
                              seasonMap[seasonNumber]!
                                  .map((entry) => entry.index)
                                  .toList(),
                            );
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(
                                alpha:
                                    seasonMap[seasonNumber]!.every(
                                      (entry) =>
                                          selectedIndices.contains(entry.index),
                                    )
                                    ? 0.9
                                    : seasonMap[seasonNumber]!.any(
                                        (entry) => selectedIndices.contains(
                                          entry.index,
                                        ),
                                      )
                                    ? 0.4
                                    : 0,
                              ),
                              borderRadius: app.shape.br(6),
                              border: Border.all(
                                color: const Color(0xFF10B981),
                                width: 2,
                              ),
                            ),
                            child:
                                seasonMap[seasonNumber]!.every(
                                  (entry) =>
                                      selectedIndices.contains(entry.index),
                                )
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : seasonMap[seasonNumber]!.any(
                                    (entry) =>
                                        selectedIndices.contains(entry.index),
                                  )
                                ? const Icon(
                                    Icons.remove,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: app.shape.br(16),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Season $seasonNumber',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${seasonMap[seasonNumber]!.length} episodes',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.grey[500],
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (otherEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            _deps.buildSectionHeader('Extras'),
            const SizedBox(height: 12),
            for (int i = 0; i < otherEntries.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: _deps.buildTorboxFileCard(
                  entry: otherEntries[i],
                  isSelected: selectedIndices.contains(otherEntries[i].index),
                  onToggle: () => onToggleFile(otherEntries[i].index),
                  animationIndex: i,
                  surface: app.cloud.dialogSurface,
                  subtitle: otherEntries[i].file.name,
                  badge: 'Extra',
                  onCopy: onCopy == null ? null : () => onCopy(otherEntries[i]),
                ),
              ),
          ],
        ],
      );
    }

    final chosenSeasonEntries = seasonMap[currentSeason] ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => onSeasonChange(null),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF6366F1),
                ),
                label: const Text(
                  'Back to seasons',
                  style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Season $currentSeason',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            itemCount: chosenSeasonEntries.length,
            itemBuilder: (context, index) {
              final entry = chosenSeasonEntries[index];
              final info = entry.seriesInfo;
              final badge = info.episode != null
                  ? 'E${info.episode.toString().padLeft(2, '0')}'
                  : null;
              return Container(
                key: ValueKey('torbox-episode-${entry.index}'),
                margin: const EdgeInsets.only(bottom: 12),
                child: _deps.buildTorboxFileCard(
                  entry: entry,
                  isSelected: selectedIndices.contains(entry.index),
                  onToggle: () => onToggleFile(entry.index),
                  animationIndex: index,
                  surface: app.cloud.dialogSurface,
                  badge: badge,
                  onCopy: onCopy == null ? null : () => onCopy(entry),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
