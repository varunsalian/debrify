import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/dialog_tap_guard.dart';

enum SourceRowActionKind { torrent, addon, iptv, mediaServer, external }

/// Row actions only: eligibility and playback/persistence stay with callers.
/// Capture the opening view's theme across the modal route, as before.
class SourceRowActionsSheet extends StatelessWidget {
  const SourceRowActionsSheet({
    super.key,
    required this.app,
    required this.kind,
    required this.bound,
    required this.onPlay,
    this.onTogglePin,
    this.onCopy,
    this.onDownload,
  });

  final AppTheme app;
  final SourceRowActionKind kind;
  final bool bound;
  final VoidCallback onPlay;
  final VoidCallback? onTogglePin;
  final VoidCallback? onCopy;
  final VoidCallback? onDownload;

  bool get _torrent => kind == SourceRowActionKind.torrent;
  bool get _external => kind == SourceRowActionKind.external;

  String get _pinSubtitle {
    if (_torrent) {
      return bound
          ? 'Stop reusing this source'
          : 'Reuse this source for instant playback';
    }
    if (bound) return 'Stop refreshing this stream for playback';
    return switch (kind) {
      SourceRowActionKind.mediaServer =>
        'Resolve this version from your media server when played',
      SourceRowActionKind.iptv =>
        'Resolve it from this IPTV catalog when played',
      _ => 'Re-fetch a fresh link from this addon when played',
    };
  }

  void _activate(BuildContext context, VoidCallback action) {
    DialogTapGuard.markKeyAction();
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(
            _external ? Icons.open_in_new_rounded : Icons.play_arrow_rounded,
            color: app.core.tx,
          ),
          title: Text(
            _torrent
                ? 'Play'
                : _external
                ? 'Open externally'
                : 'Play now',
          ),
          subtitle: _torrent
              ? null
              : Text(
                  _external
                      ? 'Open this link in your browser'
                      : 'Stream directly — no debrid needed',
                  style: TextStyle(color: app.fade(app.core.tx, 0.5)),
                ),
          onTap: () => _activate(context, onPlay),
        ),
        if (!_external && onTogglePin != null)
          ListTile(
            leading: Icon(
              bound ? Icons.link_off_rounded : Icons.link_rounded,
              color: const Color(0xFFF59E0B),
            ),
            title: Text(bound ? 'Unpin source' : 'Pin as source'),
            subtitle: Text(
              _pinSubtitle,
              style: TextStyle(color: app.fade(app.core.tx, 0.5)),
            ),
            onTap: () => _activate(context, onTogglePin!),
          ),
        if (onCopy != null)
          ListTile(
            leading: const Icon(Icons.copy_rounded, color: Color(0xFFF59E0B)),
            title: const Text('Copy link'),
            onTap: () => _activate(context, onCopy!),
          ),
        if (onDownload != null)
          ListTile(
            leading: const Icon(
              Icons.download_rounded,
              color: Color(0xFF60A5FA),
            ),
            title: const Text('Download to device'),
            subtitle: Text(
              'Save this stream to your device',
              style: TextStyle(color: app.fade(app.core.tx, 0.5)),
            ),
            onTap: () => _activate(context, onDownload!),
          ),
      ],
    ),
  );
}
