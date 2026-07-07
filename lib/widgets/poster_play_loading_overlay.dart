import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Cinematic "finding the best source" mask for catalog auto-play: the title's
/// poster fills the screen (blurred + darkened), with a provider-accent spinner,
/// the title, a status line, and an optional Cancel button. Mirrors Home's
/// `_buildQuickPlayMovieMask` so catalog Play from the Search tab looks identical
/// instead of showing a bare name-only overlay.
///
/// Handle-based so dismissal is idempotent: [dismiss] pops exactly once whether
/// called by the flow on completion or by the Cancel button — never double-pops
/// the route underneath (the detail page).
class PosterPlayLoadingOverlay {
  final BuildContext _context;
  bool _dismissed = false;
  PosterPlayLoadingOverlay._(this._context);

  static PosterPlayLoadingOverlay show(
    BuildContext context, {
    String? posterUrl,
    required String title,
    required String provider,
    required Color accentColor,
    required IconData icon,
    VoidCallback? onCancel,
  }) {
    final handle = PosterPlayLoadingOverlay._(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => PopScope(
        // Back is a no-op during the resolve window; the caller's explicit
        // dismiss() drives the single pop, matching the loading-overlay pairing.
        canPop: false,
        child: _PosterLoadingContent(
          posterUrl: posterUrl,
          title: title,
          provider: provider,
          accentColor: accentColor,
          icon: icon,
          onCancel: onCancel == null
              ? null
              : () {
                  handle.dismiss();
                  onCancel();
                },
        ),
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
    return handle;
  }

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    final nav = Navigator.of(_context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }
}

class _PosterLoadingContent extends StatefulWidget {
  final String? posterUrl;
  final String title;
  final String provider;
  final Color accentColor;
  final IconData icon;
  final VoidCallback? onCancel;

  const _PosterLoadingContent({
    required this.posterUrl,
    required this.title,
    required this.provider,
    required this.accentColor,
    required this.icon,
    required this.onCancel,
  });

  @override
  State<_PosterLoadingContent> createState() => _PosterLoadingContentState();
}

class _PosterLoadingContentState extends State<_PosterLoadingContent> {
  @override
  Widget build(BuildContext context) {
    final hasPoster = widget.posterUrl != null && widget.posterUrl!.isNotEmpty;
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Poster backdrop — blurred + darkened so the foreground reads.
          if (hasPoster)
            Image.network(
              widget.posterUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (hasPoster)
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: const SizedBox.expand(),
            ),
          // Vignette + bottom scrim.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black.withValues(alpha: 0.9),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                // Small poster card, centered.
                if (hasPoster)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 130,
                      height: 195,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: widget.accentColor.withValues(alpha: 0.35),
                            blurRadius: 32,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Image.network(
                        widget.posterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.white.withValues(alpha: 0.06),
                          child: Icon(widget.icon,
                              color: widget.accentColor, size: 40),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation(widget.accentColor),
                  ),
                ),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Finding the best source…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'via ${widget.provider}',
                  style: TextStyle(
                    color: widget.accentColor.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (widget.onCancel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: TextButton(
                      onPressed: widget.onCancel,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
