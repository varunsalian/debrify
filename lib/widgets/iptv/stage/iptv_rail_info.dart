import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/debrify_image_cache.dart';
import '../../../theme/app_theme_scope.dart';
import '../../browse/brand_accent.dart';
import '../iptv_epg_panel.dart';

/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)"
/// — pulled out of the rail's big title into its sub-line (the channel rows do
/// the same split for themselves).
final RegExp iptvRailResolutionExp = RegExp(
  r'\((\d{3,4}[pi])\)',
  caseSensitive: false,
);

/// Identity block under the stage: logo chip, channel name (resolution pulled
/// out into the sub-line), group. Empty when nothing is focused yet.
class IptvRailInfo extends StatelessWidget {
  final IptvChannel? channel;
  const IptvRailInfo({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final ch = channel;
    if (ch == null) return const SizedBox.shrink();
    final brand = brandAccentFor(ch.name);

    final resMatch = iptvRailResolutionExp.firstMatch(ch.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final cleanName = resMatch == null
        ? ch.name
        : ch.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final displayName = ch.channelNumber == null
        ? cleanName
        : 'CH ${ch.channelNumber}  $cleanName';
    final group = ch.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: app.shape.br(11),
                border: Border.all(color: app.core.tx.withValues(alpha: 0.06)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      brand.withValues(alpha: 0.16),
                      app.iptv.logoPlate,
                    ),
                    // The plate's lower stop — value-equal to iptv.modalBg,
                    // but that role is a dialog ground and must not repaint
                    // logos when a theme moves its sheets.
                    const Color(0xFF14141D),
                  ],
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: (ch.logoUrl != null && ch.logoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: ch.logoUrl!,
                        cacheManager: DebrifyImageCache.iptvLogos,
                        fit: BoxFit.contain,
                        // Cap the decode — see the row logo chip's rationale.
                        memCacheHeight: 96,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.live_tv_rounded,
                          size: 20,
                          color: brand.withValues(alpha: 0.85),
                        ),
                      )
                    : Icon(
                        Icons.live_tv_rounded,
                        size: 20,
                        color: brand.withValues(alpha: 0.85),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (subParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subParts.join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx.withValues(alpha: 0.52),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // What's on: now/next for the focused channel. Renders nothing for
        // channels without guide data, so the rail is unchanged for those.
        const SizedBox(height: 14),
        Flexible(child: IptvRailEpgCard(channel: ch)),
      ],
    );
  }
}
