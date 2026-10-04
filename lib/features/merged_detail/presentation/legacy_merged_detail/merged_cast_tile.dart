import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/merged_detail/presentation/merged_focus_halo.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:flutter/material.dart';

/// Cast avatar — focusable (no-op tap) so DPAD-down can walk the info column
/// through it, with a visible gold ring while focused.
class _CastTile extends StatefulWidget {
  final CastMember member;
  final Color fallback;
  const _CastTile({required this.member, required this.fallback});

  @override
  State<_CastTile> createState() => _CastTileState();
}

class _CastTileState extends State<_CastTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          MergedFocusHalo(
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

typedef MergedCastTile = _CastTile;

const mergedCastTileConstructor = _CastTile.new;
