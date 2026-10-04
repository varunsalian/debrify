import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/merged_detail/presentation/merged_focus_halo.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/widgets/movie_watched_badge.dart';
import 'package:flutter/material.dart';

/// "More Like This" poster card — gold ring + slight scale while focused so the
/// DPAD cursor is unmistakable over artwork.
class _RecCard extends StatefulWidget {
  final StremioMeta rec;
  final Color fallback;
  final VoidCallback onTap;
  const _RecCard({
    required this.rec,
    required this.fallback,
    required this.onTap,
  });

  @override
  State<_RecCard> createState() => _RecCardState();
}

class _RecCardState extends State<_RecCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    return SizedBox(
      width: 100,
      child: MergedFocusHalo(
        focused: _focused,
        radius: BorderRadius.circular(10),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (rec.poster != null && rec.poster!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: rec.poster!,
                      fit: BoxFit.cover,
                      cacheManager: DebrifyImageCache.manager,
                      // 100 logical px card (up to dpr 3 on phones) — decode
                      // small so ten posters at once don't lean on a 2GB box.
                      memCacheWidth: 300,
                      placeholder: (_, __) => Container(color: widget.fallback),
                      errorWidget: (_, __, ___) =>
                          Container(color: widget.fallback),
                    )
                  else
                    Container(color: widget.fallback),
                  if (rec.type == 'movie' || rec.type == 'series')
                    Positioned(
                      top: 6,
                      right: 6,
                      child: MovieWatchedBadge(
                        imdbId: rec.effectiveImdbId ?? rec.id,
                        contentType: rec.type,
                        compact: true,
                        tickPolicyScoped: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef MergedRecCard = _RecCard;

const mergedRecCardConstructor = _RecCard.new;
