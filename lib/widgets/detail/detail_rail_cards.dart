// Extracted verbatim from lib/screens/merged_series_detail_screen.dart
// (that screen's private presentational tail). Behaviour is unchanged; the
// only edits are the renames that make these public and the parameters that
// replace the host's private members.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../movie_watched_badge.dart';
import 'detail_focus_chrome.dart';

/// Cast avatar — focusable (no-op tap) so DPAD-down can walk the info column
/// through it, with a visible gold ring while focused.
class DetailCastTile extends StatefulWidget {
  final CastMember member;
  final Color fallback;
  const DetailCastTile({
    super.key,
    required this.member,
    required this.fallback,
  });

  @override
  State<DetailCastTile> createState() => _DetailCastTileState();
}

class _DetailCastTileState extends State<DetailCastTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          DetailFocusHalo(
            focused: _focused,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {},
                onFocusChange: (f) => setState(() => _focused = f),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: (m.imageUrl != null && m.imageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: m.imageUrl!,
                          fit: BoxFit.cover,
                          cacheManager: DebrifyImageCache.manager,
                          // 56 logical px avatar (up to dpr 3 on phones) —
                          // never decode a full-res headshot.
                          memCacheWidth: 180,
                          placeholder: (_, __) =>
                              Container(color: widget.fallback),
                          errorWidget: (_, __, ___) =>
                              Container(color: widget.fallback),
                        )
                      : Container(
                          color: widget.fallback,
                          child: Icon(Icons.person, color: Colors.white38),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            m.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _focused ? Colors.white : Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// "More Like This" poster card — gold ring + slight scale while focused so the
/// DPAD cursor is unmistakable over artwork.
class DetailRecCard extends StatefulWidget {
  final StremioMeta rec;
  final Color fallback;
  final VoidCallback onTap;
  const DetailRecCard({
    super.key,
    required this.rec,
    required this.fallback,
    required this.onTap,
  });

  @override
  State<DetailRecCard> createState() => _DetailRecCardState();
}

class _DetailRecCardState extends State<DetailRecCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    return SizedBox(
      width: 100,
      child: DetailFocusHalo(
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

/// The focused episode's frame, painted over the title artwork.
///
/// Switches instantly on TV: a fullscreen animated opacity per DPAD move is
/// exactly what the TV cost budget forbids. Off-TV it cross-fades.
class DetailAmbientStill extends StatelessWidget {
  final String url;
  final bool isTelevision;

  const DetailAmbientStill({
    super.key,
    required this.url,
    required this.isTelevision,
  });

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      fit: BoxFit.cover,
      cacheManager: DebrifyImageCache.manager,
      memCacheWidth: 1280,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
    );
    if (isTelevision) return image;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      // The default layout centres children under LOOSE constraints, so a
      // BoxFit.cover image would size itself to its own aspect and letterbox.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: image,
    );
  }
}
