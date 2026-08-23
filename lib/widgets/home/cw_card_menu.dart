import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/themed_artwork.dart';
import '../../utils/dialog_tap_guard.dart';
import '../../utils/tv_keys.dart';

/// What [showCwCardMenu] came back with (null = dismissed).
enum CwCardAction { play, remove }

/// The long-press menu for a Continue Watching card on Home.
///
/// A centered dialog rather than a bottom sheet so one presentation serves
/// every size: it's the same chrome the IPTV list picker uses (the app's other
/// "hold to open a menu" gesture), which keeps the DPAD story identical — first
/// row focused on open, up/down between rows, Back to dismiss.
///
/// The copy is passed in rather than derived here: a Continue Watching row can
/// be local, Trakt, Simkl or IPTV, and "remove" means something different in
/// each (see the callers in `search_screen.dart`).
Future<CwCardAction?> showCwCardMenu(
  BuildContext context, {
  required String title,
  required bool isTelevision,
  required String playDescription,
  required String removeDescription,
  String? posterUrl,
  String? subtitle,

  /// False on PikPak-only setups, where the board hides quick-play entirely —
  /// the menu then exists purely to offer the removal.
  bool showPlay = true,
  bool showRemove = true,
  String playLabel = 'Play',
  String removeLabel = 'Remove from Continue Watching',
}) {
  return showDialog<CwCardAction>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CwCardMenu(
      title: title,
      isTelevision: isTelevision,
      posterUrl: posterUrl,
      subtitle: subtitle,
      showPlay: showPlay,
      showRemove: showRemove,
      playLabel: playLabel,
      playDescription: playDescription,
      removeLabel: removeLabel,
      removeDescription: removeDescription,
    ),
  );
}

class _CwCardMenu extends StatefulWidget {
  final String title;
  final bool isTelevision;
  final String? posterUrl;
  final String? subtitle;
  final bool showPlay;
  final bool showRemove;
  final String playLabel;
  final String playDescription;
  final String removeLabel;
  final String removeDescription;

  const _CwCardMenu({
    required this.title,
    required this.isTelevision,
    required this.posterUrl,
    required this.subtitle,
    required this.showPlay,
    required this.showRemove,
    required this.playLabel,
    required this.playDescription,
    required this.removeLabel,
    required this.removeDescription,
  });

  @override
  State<_CwCardMenu> createState() => _CwCardMenuState();
}

class _CwCardMenuState extends State<_CwCardMenu> {
  static const _accent = Color(0xFF8B5CF6);
  static const _danger = Color(0xFFF87171);

  final FocusNode _playNode = FocusNode(debugLabel: 'cw-menu-play');
  final FocusNode _removeNode = FocusNode(debugLabel: 'cw-menu-remove');

  @override
  void initState() {
    super.initState();
    // TV only: land the DPAD on the first row, never on the barrier — that
    // would leave the remote with nothing to press but Back. Touch/desktop open
    // with nothing highlighted, so no row reads as pre-selected.
    if (!widget.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (widget.showPlay ? _playNode : _removeNode).requestFocus();
    });
  }

  @override
  void dispose() {
    _playNode.dispose();
    _removeNode.dispose();
    super.dispose();
  }

  void _pick(CwCardAction action) => Navigator.of(context).pop(action);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final app = AppThemeScope.of(context);
    // Phones take the full width (minus the inset); anything wider caps at a
    // comfortable reading width so the rows never stretch into a banner.
    final maxWidth = size.width < 520 ? size.width : 430.0;
    return Dialog(
      // Tokenised with the ink, not after it: the rows below now draw their
      // text from `app.core.tx`, so a surface pinned dark would put a light
      // theme's near-black text on a near-black sheet.
      backgroundColor: app.sheetSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: app.shape.br(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                if (widget.showPlay)
                  _MenuRow(
                    focusNode: _playNode,
                    icon: Icons.play_arrow_rounded,
                    iconColor: _accent,
                    accent: _accent,
                    label: widget.playLabel,
                    description: widget.playDescription,
                    onTap: () => _pick(CwCardAction.play),
                  ),
                if (widget.showRemove)
                  _MenuRow(
                    focusNode: _removeNode,
                    icon: Icons.playlist_remove_rounded,
                    iconColor: _danger,
                    accent: _danger,
                    label: widget.removeLabel,
                    description: widget.removeDescription,
                    onTap: () => _pick(CwCardAction.remove),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final app = AppThemeScope.of(context);
    final poster = widget.posterUrl;
    final subtitle = widget.subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 44,
          height: 66,
          // The poster's frame is the theme's, so [ThemedArtwork] owns the
          // clip this site used to draw for itself.
          child: ThemedArtwork(
            role: ArtRole.poster,
            radius: 8,
            builder: (context, blend) => (poster != null && poster.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: poster,
                    fit: BoxFit.cover,
                    color: blend?.$1,
                    colorBlendMode: blend?.$2,
                    memCacheWidth: 132,
                    fadeInDuration: Duration.zero,
                    placeholder: (_, __) => const _PosterFallback(),
                    errorWidget: (_, __, ___) => const _PosterFallback(),
                  )
                : const _PosterFallback(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.5),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return ColoredBox(
      color: app.fade(app.core.tx, 0.06),
      child: Icon(
        Icons.movie_rounded,
        size: 18,
        color: app.fade(app.core.tx, 0.3),
      ),
    );
  }
}

/// One focusable action row. Focus is drawn with the accent ring the TV
/// pickers use, so DPAD position is never ambiguous.
class _MenuRow extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final Color iconColor;
  final Color accent;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _MenuRow({
    required this.focusNode,
    required this.icon,
    required this.iconColor,
    required this.accent,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateOrSpaceKey(event.logicalKey)) {
          // DPAD Select also synthesizes a tap; mark it so the tap that
          // follows this key action doesn't fire the row a second time.
          DialogTapGuard.markKeyAction();
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (DialogTapGuard.shouldIgnoreTap()) return;
            widget.onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: _active
                  ? widget.accent.withValues(alpha: 0.16)
                  : app.fade(app.core.tx, 0.04),
              borderRadius: app.shape.br(14),
              border: Border.all(
                color: _active ? widget.accent : app.fade(app.core.tx, 0.07),
                width: _active ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(widget.icon, size: 22, color: widget.iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.description,
                        style: TextStyle(
                          color: app.fade(app.core.tx, 0.5),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
