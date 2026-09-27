import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/home/home_theme.dart';

/// The hero's title, IMAGE-FIRST: the studio title-treatment art when a
/// `logo` URL is known, the plain text title only when it is genuinely
/// unavailable (no URL, or the fetch failed). While the art is in flight the
/// slot holds EMPTY — never the text — because text-flashing-then-swapping
/// to the image read as a glitch (the old behaviour). Failed URLs are
/// remembered for the session so revisiting a logo-less title shows its text
/// immediately instead of re-probing (and re-flashing empty) every time.
/// Bottom-left anchored in a fixed-height slot so successive titles sit on
/// one baseline as DPAD focus flies.
class HomeHeroTitleArt extends StatefulWidget {
  final String title;
  final String? logoUrl;
  final bool compact;
  final bool isTelevision;

  const HomeHeroTitleArt({
    super.key,
    required this.title,
    required this.logoUrl,
    required this.compact,
    required this.isTelevision,
  });

  @override
  State<HomeHeroTitleArt> createState() => _HomeHeroTitleArtState();
}

class _HomeHeroTitleArtState extends State<HomeHeroTitleArt> {
  /// Session-wide memo of logo URLs that 404'd (metahub simply has no art
  /// for many titles) — those heroes go straight to text with no empty beat
  /// and no repeat network probe on every DPAD revisit.
  static final Set<String> _deadLogoUrls = <String>{};

  Text _titleText(int maxLines) => Text(
    widget.title,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    // Poppins (rounded geometric) for the display title, airier and lighter
    // than Inter-w800/-1 tracking — closer to Stremio's hero. Body/metadata
    // stay on the Inter theme.
    style: GoogleFonts.poppins(
      fontSize: widget.compact
          ? (widget.isTelevision ? 24 : 20)
          : (widget.isTelevision ? 38 : 26),
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.06,
      color: AppThemeScope.of(context).core.tx,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final logo = widget.logoUrl;
    final compact = widget.compact;
    final isTelevision = widget.isTelevision;
    if (logo == null || logo.isEmpty || _deadLogoUrls.contains(logo)) {
      // Known-no-art: the full two-line text title, exactly the old look.
      return _titleText(2);
    }
    final logoH = compact
        ? (isTelevision ? 46.0 : 38.0)
        : (isTelevision ? 76.0 : 58.0);
    return SizedBox(
      height: logoH,
      width: double.infinity,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isTelevision ? 320 : 280),
          child: CachedNetworkImage(
            imageUrl: logo,
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            // Logos are wide PNGs (metahub ~800px) shown ~300px at most — cap
            // the decode like every other art surface.
            memCacheWidth: 480,
            fadeInDuration: HomeTheme.imageFadeIn(isTelevision),
            fadeOutDuration: HomeTheme.imageFadeOut(isTelevision),
            // Empty while loading AND on error: the error frame only shows
            // for the instant before errorListener rebuilds us onto the
            // full-size text path below (a slot-cramped one-line fallback
            // here would flash before that swap).
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
            errorListener: (_) {
              _deadLogoUrls.add(logo);
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
  }
}
