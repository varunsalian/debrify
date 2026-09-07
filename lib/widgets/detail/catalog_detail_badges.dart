/// The small metadata ornaments on `CatalogItemDetailScreen`: the certificate
/// badge, the genre chip, the Metacritic score and the cast avatar.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/imdb_enrichment_service.dart';

// ── Certificate badge ──────────────────────────────────────────────────────

class CatalogDetailCertBadge extends StatelessWidget {
  final String label;
  const CatalogDetailCertBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.50),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          height: 1.3,
        ),
      ),
    );
  }
}

// ── Genre chip ──────────────────────────────────────────────────────────────

class CatalogDetailGenreChip extends StatelessWidget {
  final String label;
  const CatalogDetailGenreChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Metacritic badge ──────────────────────────────────────────────────────

class CatalogDetailMetacriticBadge extends StatelessWidget {
  final int score;
  const CatalogDetailMetacriticBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (score >= 61) {
      bg = const Color(0xFF66CC33);
    } else if (score >= 40) {
      bg = const Color(0xFFFFCC33);
    } else {
      bg = const Color(0xFFFF0000);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1.3,
        ),
      ),
    );
  }
}

// ── Cast avatar ──────────────────────────────────────────────────────────

class CatalogDetailCastAvatar extends StatelessWidget {
  final CastMember member;
  final double size;
  const CatalogDetailCastAvatar({
    super.key,
    required this.member,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 8),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: member.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: member.imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _initials(),
                    errorWidget: (_, __, ___) => _initials(),
                  )
                : _initials(),
          ),
          const SizedBox(height: 6),
          Text(
            member.name.split(' ').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (member.character != null) ...[
            const SizedBox(height: 1),
            Text(
              member.character!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.38),
                fontSize: 9,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _initials() => Center(
    child: Text(
      member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
