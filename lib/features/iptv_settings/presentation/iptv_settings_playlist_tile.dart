import 'package:debrify/features/iptv_settings/presentation/iptv_settings_icon_button.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_reveal.dart';
import 'package:flutter/material.dart';

/// Focusable playlist tile with star and delete buttons
class IptvSettingsPlaylistTile extends StatefulWidget {
  const IptvSettingsPlaylistTile({
    required this.playlist,
    required this.isDefault,
    this.isRefreshing = false,
    this.starFocusNode,
    this.refreshFocusNode,
    this.editFocusNode,
    this.deleteFocusNode,
    required this.onSetDefault,
    this.onRefresh,
    this.onEdit,
    this.onDelete,
  });

  final IptvPlaylist playlist;
  final bool isDefault;
  final bool isRefreshing;
  final FocusNode? starFocusNode;
  final FocusNode? refreshFocusNode;
  final FocusNode? editFocusNode;
  final FocusNode? deleteFocusNode;
  final VoidCallback onSetDefault;
  // Null when the playlist cannot be refreshed (local-file playlists).
  final VoidCallback? onRefresh;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<IptvSettingsPlaylistTile> createState() =>
      _FocusablePlaylistTileState();
}

class _FocusablePlaylistTileState extends State<IptvSettingsPlaylistTile> {
  bool _starFocused = false;
  bool _refreshFocused = false;
  bool _editFocused = false;
  bool _deleteFocused = false;

  @override
  void initState() {
    super.initState();
    widget.starFocusNode?.addListener(_onStarFocusChange);
    widget.refreshFocusNode?.addListener(_onRefreshFocusChange);
    widget.editFocusNode?.addListener(_onEditFocusChange);
    widget.deleteFocusNode?.addListener(_onDeleteFocusChange);
  }

  @override
  void didUpdateWidget(covariant IptvSettingsPlaylistTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.starFocusNode != widget.starFocusNode) {
      oldWidget.starFocusNode?.removeListener(_onStarFocusChange);
      widget.starFocusNode?.addListener(_onStarFocusChange);
    }
    if (oldWidget.refreshFocusNode != widget.refreshFocusNode) {
      oldWidget.refreshFocusNode?.removeListener(_onRefreshFocusChange);
      widget.refreshFocusNode?.addListener(_onRefreshFocusChange);
    }
    if (oldWidget.editFocusNode != widget.editFocusNode) {
      oldWidget.editFocusNode?.removeListener(_onEditFocusChange);
      widget.editFocusNode?.addListener(_onEditFocusChange);
    }
    if (oldWidget.deleteFocusNode != widget.deleteFocusNode) {
      oldWidget.deleteFocusNode?.removeListener(_onDeleteFocusChange);
      widget.deleteFocusNode?.addListener(_onDeleteFocusChange);
    }
  }

  @override
  void dispose() {
    widget.starFocusNode?.removeListener(_onStarFocusChange);
    widget.refreshFocusNode?.removeListener(_onRefreshFocusChange);
    widget.editFocusNode?.removeListener(_onEditFocusChange);
    widget.deleteFocusNode?.removeListener(_onDeleteFocusChange);
    super.dispose();
  }

  void _onStarFocusChange() {
    if (mounted) {
      final hasFocus = widget.starFocusNode?.hasFocus ?? false;
      setState(() => _starFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _onRefreshFocusChange() {
    if (mounted) {
      final hasFocus = widget.refreshFocusNode?.hasFocus ?? false;
      setState(() => _refreshFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _onEditFocusChange() {
    if (mounted) {
      final hasFocus = widget.editFocusNode?.hasFocus ?? false;
      setState(() => _editFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _onDeleteFocusChange() {
    if (mounted) {
      final hasFocus = widget.deleteFocusNode?.hasFocus ?? false;
      setState(() => _deleteFocused = hasFocus);
      if (hasFocus) _ensureVisible();
    }
  }

  void _ensureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        // Minimal, not centering: alignment 0.5 re-scrolled the page on
        // EVERY tile-button focus even when the tile was fully visible.
        tvRevealMinimal(context, duration: const Duration(milliseconds: 200));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final isAnyFocused =
        _starFocused || _refreshFocused || _editFocused || _deleteFocused;
    final canRefresh = widget.onRefresh != null;

    // Snap, don't tween — TV GPU rule.
    return Container(
      decoration: BoxDecoration(
        color: isAnyFocused ? t.panel2 : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          widget.isDefault
              ? Icons.star
              : widget.playlist.isXtreamCodes
              ? Icons.login
              : (widget.playlist.isLocalFile
                    ? Icons.folder
                    : Icons.playlist_play),
          color: widget.isDefault ? t.warning : null,
        ),
        title: Text(widget.playlist.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.playlist.credentialsRedacted) ...[
                  Icon(Icons.lock_outline, size: 12, color: t.dim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Shared connection • credentials hidden',
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
                ] else if (widget.playlist.isXtreamCodes) ...[
                  Icon(Icons.login, size: 12, color: t.dim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Xtream Codes - ${widget.playlist.serverUrl}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
                ] else if (widget.playlist.isLocalFile) ...[
                  Icon(Icons.sd_card, size: 12, color: t.dim),
                  const SizedBox(width: 4),
                  Text(
                    'Local file',
                    style: TextStyle(fontSize: 12, color: t.dim),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      widget.playlist.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.dim),
                    ),
                  ),
              ],
            ),
            if ((widget.playlist.epgUrl ?? '').isNotEmpty)
              Text(
                'Custom EPG URL set',
                style: TextStyle(color: t.dim, fontSize: 12),
              ),
            if (widget.isDefault)
              Text(
                'Default playlist',
                style: TextStyle(color: t.warning, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IptvSettingsIconButton(
              focusNode: widget.starFocusNode,
              icon: widget.isDefault ? Icons.star : Icons.star_border,
              color: widget.isDefault ? t.warning : null,
              tooltip: widget.isDefault ? 'Remove default' : 'Set as default',
              onPressed: widget.onSetDefault,
              onRightArrow: () =>
                  (canRefresh ? widget.refreshFocusNode : widget.editFocusNode)
                      ?.requestFocus(),
            ),
            if (canRefresh)
              IptvSettingsIconButton(
                focusNode: widget.refreshFocusNode,
                icon: Icons.refresh,
                tooltip: 'Refresh playlist',
                isBusy: widget.isRefreshing,
                onPressed: widget.onRefresh!,
                onLeftArrow: () => widget.starFocusNode?.requestFocus(),
                onRightArrow: () => widget.editFocusNode?.requestFocus(),
              ),
            if (widget.onEdit != null)
              IptvSettingsIconButton(
                focusNode: widget.editFocusNode,
                icon: Icons.edit_outlined,
                tooltip: 'Edit playlist',
                onPressed: widget.onEdit,
                onLeftArrow: () =>
                    (canRefresh
                            ? widget.refreshFocusNode
                            : widget.starFocusNode)
                        ?.requestFocus(),
                onRightArrow: () => widget.deleteFocusNode?.requestFocus(),
              ),
            if (widget.onDelete != null)
              IptvSettingsIconButton(
                focusNode: widget.deleteFocusNode,
                icon: Icons.delete_outline,
                tooltip: 'Remove playlist',
                onPressed: widget.onDelete,
                onLeftArrow: () => widget.editFocusNode?.requestFocus(),
              ),
          ],
        ),
      ),
    );
  }
}
