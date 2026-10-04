import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:flutter/material.dart';

class _CastAvatar extends StatelessWidget {
  final CastMember member;
  final double size;
  const _CastAvatar({required this.member, required this.size});

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

typedef CatalogCastAvatar = _CastAvatar;

const catalogCastAvatarConstructor = _CastAvatar.new;
