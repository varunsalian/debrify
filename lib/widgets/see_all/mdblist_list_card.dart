import 'package:flutter/material.dart';

import '../../services/mdblist/mdblist_list_source.dart';

/// The Stremio purple accent, matching `kStremioAccent` in search_screen.
const Color _accent = Color(0xFF7B5CFF);

/// A single MDBList "list" rendered as a 2:3 gradient card — the same footprint
/// as the poster cards, but for a *collection* (which has no artwork): a list
/// glyph, the list name centred, an optional owner line, and an items/likes
/// footer. Shared by the search results rail and the lists See-All grid so the
/// two stay visually identical.
///
/// Focus/hover highlight is driven by [focused] (the caller owns focus state);
/// [onTap] opens the list.
class MdblistListCard extends StatelessWidget {
  final MdblistListChoice list;
  final bool focused;
  final VoidCallback onTap;

  const MdblistListCard({
    super.key,
    required this.list,
    required this.onTap,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    final footer = [
      '${list.itemCount} items',
      if (list.likes > 0) '♥ ${list.likes}',
    ].join('  ·  ');

    // The card is a fixed-height 2:3 tile with non-flexible content (icon +
    // name + owner + footer). At the smallest TV card size, or under a large
    // accessibility font scale, an unclamped scale would overflow the column —
    // so cap the text scaling for this compact tile.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accent.withValues(alpha: focused ? 0.34 : 0.20),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? _accent : Colors.white.withValues(alpha: 0.10),
            width: focused ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                Icons.playlist_play_rounded,
                size: 32,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const Spacer(),
            Text(
              list.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            if (list.ownerName != null) ...[
              const SizedBox(height: 3),
              Text(
                'by ${list.ownerName}',
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11.5,
                ),
              ),
            ],
            const Spacer(),
            Text(
              footer,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
