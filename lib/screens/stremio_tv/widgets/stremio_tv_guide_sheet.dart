import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';

/// Bottom sheet showing a mini channel guide — current + upcoming items
/// with start/end times, poster thumbnails, and metadata.
class StremioTvGuideSheet extends StatelessWidget {
  final StremioTvChannel channel;
  final List<StremioTvNowPlaying> schedule;
  final void Function(int index)? onItemTap;

  const StremioTvGuideSheet({
    super.key,
    required this.channel,
    required this.schedule,
    this.onItemTap,
  });

  /// Show the guide as a modal bottom sheet. Returns the tapped item index.
  static Future<int?> show(
    BuildContext context, {
    required StremioTvChannel channel,
    required List<StremioTvNowPlaying> schedule,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StremioTvGuideSheet(
        channel: channel,
        schedule: schedule,
        onItemTap: (index) => Navigator.of(context).pop(index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.7;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.live_tv_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.addon.name,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          channel.genre != null
                              ? '${channel.catalog.name} - ${channel.genre}'
                              : channel.catalog.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(
              height: 16,
              indent: 20,
              endIndent: 20,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            // Schedule list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: schedule.length,
                itemBuilder: (context, index) {
                  final entry = schedule[index];
                  final isCurrent = index == 0;
                  return _GuideEntry(
                    entry: entry,
                    isCurrent: isCurrent,
                    onTap: isCurrent && onItemTap != null
                        ? () => onItemTap!(index)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideEntry extends StatelessWidget {
  final StremioTvNowPlaying entry;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _GuideEntry({
    required this.entry,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = entry.item;

    final content = Material(
      color: isCurrent
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              // Poster thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 45,
                  height: 65,
                  child: item.poster != null
                      ? CachedNetworkImage(
                          imageUrl: item.poster!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.movie_rounded, size: 18),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, size: 18),
                            ),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.movie_rounded, size: 18),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Title + metadata + time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: theme.colorScheme.primary,
                            ),
                            child: Text(
                              'NOW',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                        Expanded(
                          child: Text(
                            item.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  isCurrent ? FontWeight.bold : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Metadata row
                    _buildMetaRow(item, theme),
                    const SizedBox(height: 2),
                    // Time range
                    Text(
                      '${StremioTvNowPlaying.formatTime(entry.slotStart)} – ${StremioTvNowPlaying.formatTime(entry.slotEnd)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isCurrent
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Equalizer animation for current item
              if (isCurrent) ...[
                const SizedBox(width: 8),
                _EqualizerBars(color: theme.colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );

    // Dim future items
    if (!isCurrent) {
      return Opacity(opacity: 0.45, child: content);
    }
    return content;
  }

  Widget _buildMetaRow(StremioMeta item, ThemeData theme) {
    final parts = <String>[];
    if (item.year != null) parts.add(item.year!);
    if (item.imdbRating != null) parts.add('${item.imdbRating}');
    if (item.genres != null && item.genres!.isNotEmpty) {
      parts.add(item.genres!.first);
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        if (item.imdbRating != null) ...[
          Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade600),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            parts.join(' \u00B7 '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Animated equalizer bars — 4 bars that bounce at different speeds,
/// mimicking a "now playing" media indicator.
class _EqualizerBars extends StatefulWidget {
  final Color color;
  const _EqualizerBars({required this.color});

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Each bar has a different frequency and phase for organic movement
  static const _barParams = [
    (freq: 1.8, phase: 0.0),
    (freq: 2.5, phase: 0.4),
    (freq: 1.4, phase: 0.8),
    (freq: 2.1, phase: 1.2),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_barParams.length, (i) {
            final p = _barParams[i];
            final t = _controller.value * 2 * math.pi;
            // Combine two sine waves for more organic movement
            final v = (math.sin(t * p.freq + p.phase) + 1) / 2;
            final v2 =
                (math.sin(t * p.freq * 0.7 + p.phase + 1.0) + 1) / 2;
            final combined = (v * 0.7 + v2 * 0.3);
            final height = 3.0 + combined * 13.0; // 3..16 px
            return Container(
              width: 3,
              height: height,
              margin: EdgeInsets.only(right: i < _barParams.length - 1 ? 2 : 0),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}
