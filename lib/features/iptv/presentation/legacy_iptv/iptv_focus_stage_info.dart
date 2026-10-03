import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/iptv/application/iptv_rail_resolution.dart';
import 'package:debrify/features/iptv/presentation/iptv_rail_hints.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/browse/brand_accent.dart';
import 'package:debrify/widgets/iptv/iptv_epg_panel.dart';
import 'package:flutter/material.dart';

/// TV focus-stage identity and programme overlay. The solid lower stop keeps
/// text legible on bright channels without a blur/filter pass.
class IptvFocusStageInfo extends StatelessWidget {
  final IptvChannel channel;
  final bool hasLists;

  const IptvFocusStageInfo({
    super.key,
    required this.channel,
    this.hasLists = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final brand = brandAccentFor(channel.name);
    final resMatch = railResExp.firstMatch(channel.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? channel.name
        : channel.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final group = channel.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 250;
        final logoSize = dense ? 32.0 : 44.0;
        return ColoredBox(
          color: app.iptv.stageBg,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              dense ? 18 : 24,
              dense ? 8 : 18,
              dense ? 18 : 24,
              dense ? 7 : 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        borderRadius: app.shape.brImg(8),
                        border: Border.all(color: app.iptv.hairline),
                        color: Color.alphaBlend(
                          brand.withValues(alpha: 0.18),
                          const Color(0xFF171B19),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child:
                            (channel.logoUrl != null &&
                                channel.logoUrl!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: channel.logoUrl!,
                                cacheManager: DebrifyImageCache.iptvLogos,
                                fit: BoxFit.contain,
                                memCacheHeight: 96,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.live_tv_rounded,
                                  size: dense ? 16 : 20,
                                  color: brand.withValues(alpha: 0.85),
                                ),
                              )
                            : Icon(
                                Icons.live_tv_rounded,
                                size: dense ? 16 : 20,
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
                            channel.channelNumber == null
                                ? displayName
                                : 'CH ${channel.channelNumber}  $displayName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: app.core.tx,
                              fontSize: dense ? 15 : 19,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
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
                                fontSize: dense ? 10.5 : 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: dense ? 5 : 13),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: app.core.tx.withValues(alpha: 0.13),
                ),
                SizedBox(height: dense ? 5 : 12),
                IptvRailEpgCard(
                  channel: channel,
                  stageOverlay: true,
                  dense: dense,
                ),
                const Spacer(),
                IptvRailHints(
                  showGuide: IptvEpgService.isEpgCapable(channel),
                  hasLists: hasLists,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
