import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';

/// The Spotlight hero's identity block: title art, the meta line with its
/// IMDb chip, and the overview. Motion comes from the host: [cascade] staggers
/// each part's entrance and [fadeMeta] hides the meta and overview while the
/// boxed trailer plays.
class HomeHeroIdentity extends StatelessWidget {
  const HomeHeroIdentity({
    super.key,
    required this.titleArt,
    required this.metaParts,
    required this.rating,
    required this.description,
    required this.compact,
    required this.isTelevision,
    required this.cascade,
    required this.fadeMeta,
  });
  final Widget titleArt;
  final List<String> metaParts;
  final double? rating;
  final String? description;
  final bool compact;
  final bool isTelevision;
  final Widget Function(Widget child, double from, double to) cascade;
  final Widget Function(Widget child) fadeMeta;

  @override
  Widget build(BuildContext context) {
    final rating = this.rating; // locals, so the null checks below promote
    final description = this.description;
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cascade(titleArt, 0.08, 0.72),
        SizedBox(height: compact ? 6 : 10),
        // Meta chips + plot fade away while the ambient trailer
        // plays (boxed mode) — the title art above holds the
        // stage alone. Layout is opacity-only, so nothing
        // reflows when they go.
        fadeMeta(
          cascade(
            Row(
              children: [
                Flexible(
                  child: Text(
                    metaParts.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: app.fade(app.core.tx, 0.82),
                    ),
                  ),
                ),
                if (rating != null) ...[
                  if (metaParts.isNotEmpty) _dot(context),
                  _imdbChip(rating),
                ],
              ],
            ),
            0.2,
            0.85,
          ),
        ),
        if (description != null && description.isNotEmpty) ...[
          SizedBox(height: compact ? 6 : 10),
          fadeMeta(
            cascade(
              Text(
                description,
                maxLines: compact ? 1 : (isTelevision ? 3 : 2),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12.5 : (isTelevision ? 14.5 : 13),
                  height: compact ? 1.3 : 1.45,
                  color: app.fade(app.core.tx, 0.72),
                ),
              ),
              0.32,
              1.0,
            ),
          ),
        ],
      ],
    );
  }
}

Widget _dot(BuildContext context) {
  final app = AppThemeScope.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 9),
    child: Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, 0.4),
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// The gold IMDb mark + rating — the meta line's one piece of colour.
Widget _imdbChip(double rating) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C518),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'IMDb',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: Color(0xFF161616),
        ),
      ),
    ),
    const SizedBox(width: 5),
    Text(
      rating.toStringAsFixed(1),
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    ),
  ],
);
