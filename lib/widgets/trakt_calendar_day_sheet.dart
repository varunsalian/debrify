import 'package:flutter/material.dart';

import '../models/stremio_addon.dart';
import '../models/trakt/trakt_calendar_entry.dart';

/// Bottom sheet showing all episodes airing on a specific day.
///
/// Tapping an episode dismisses the sheet and calls [onEpisodeSelected]
/// with a [StremioMeta] built from the entry's show fields.
class TraktCalendarDaySheet extends StatelessWidget {
  const TraktCalendarDaySheet({
    super.key,
    required this.date,
    required this.entries,
    required this.onEpisodeSelected,
  });

  final DateTime date;
  final List<TraktCalendarEntry> entries;
  final void Function(StremioMeta meta) onEpisodeSelected;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]
      ..sort((a, b) => a.firstAiredLocal.compareTo(b.firstAiredLocal));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _formatFullDate(date),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) => _EpisodeRow(
                  entry: sorted[i],
                  onTap: () {
                    final meta = _buildMetaFromEntry(sorted[i]);
                    if (meta == null) return;
                    Navigator.of(ctx).pop();
                    onEpisodeSelected(meta);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static StremioMeta? _buildMetaFromEntry(TraktCalendarEntry e) {
    if (e.showImdbId == null) return null;
    return StremioMeta.fromJson({
      'id': e.showImdbId,
      'name': e.showTitle,
      'type': 'series',
      'year': e.showYear?.toString(),
      'poster': e.posterUrl,
    });
  }

  static String _formatFullDate(DateTime d) {
    const weekdays = [
      'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
    ];
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.entry, required this.onTap});

  final TraktCalendarEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(entry.firstAiredLocal);
    final badge = entry.isNewShow
        ? 'NEW SHOW'
        : entry.isSeasonPremiere
            ? 'SEASON PREMIERE'
            : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (entry.posterUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  entry.posterUrl!,
                  width: 40,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      width: 40, height: 60, child: Icon(Icons.tv)),
                ),
              )
            else
              const SizedBox(width: 40, height: 60, child: Icon(Icons.tv)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.showTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'S${entry.seasonNumber.toString().padLeft(2, '0')}E${entry.episodeNumber.toString().padLeft(2, '0')} · $time'
                    '${entry.episodeTitle != null ? ' · ${entry.episodeTitle}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime local) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
