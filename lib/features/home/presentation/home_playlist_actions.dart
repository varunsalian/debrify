import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../screens/playlist_content_view_screen.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/debrid_action_sheet.dart';
import '../application/home_playlist_controller.dart';
import '../data/home_playlist_repository.dart';
import '../models/home_playlist.dart';

typedef HomePlaylistActionsDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  HomePlaylistController Function() controller,
  Future<void> Function() reload,
  Future<void> Function(BuildContext, Map<String, dynamic>, {bool playRandom})
  play,
});

/// Playlist menus, navigation and launch latching for the saved-content row.
class HomePlaylistActions {
  HomePlaylistActions(this._deps);
  final HomePlaylistActionsDeps _deps;
  // Guards against launching a second concurrent playback while the first is
  // still resolving links (the menu closes immediately, giving no other cue).
  bool playlistLaunching = false;

  /// The full action menu for a playlist item — the same set of actions as the
  /// Home playlist section (Home is being phased out, so this row is a complete
  /// playlist manager on its own). Rendered with the post-torrent Neon action
  /// sheet: bottom sheet on phones, centered card on desktop/TV, with the
  /// first three actions as primary pills.
  Future<void> onPlaylistItemTap(HomePlaylistItem selected) async {
    if (!_deps.mounted()) return;
    final context = _deps.context();
    final item = selected.toLegacyItem();
    final playlist = _deps.controller().current;
    final isFavorited = playlist.isFavorite(selected);
    final hasProgress = playlist.hasProgress(selected);
    final isCollection = selected.isCollection;
    final title = selected.title;

    // The sheet pops itself before running an action, so route every choice
    // through the handler instead of awaiting a dialog result.
    void run(String choice) =>
        unawaited(handlePlaylistMenuChoice(choice, item, isFavorited));

    final app = AppThemeScope.of(context);
    await showDebridActionSheet(
      context,
      providerLabel: 'Playlist',
      torrentName: title,
      gradient: [app.seeAll.accent, app.seeAll.accent2],
      providerIcon: Icons.playlist_play_rounded,
      subtitle: isCollection
          ? 'Saved collection. Choose your next step.'
          : 'Saved item. Choose your next step.',
      actions: [
        DebridActionItem(
          icon: Icons.play_circle_fill_rounded,
          color: const Color(0xFF10B981),
          title: 'Play',
          subtitle: 'Start playback',
          onTap: () => run('play'),
        ),
        if (isCollection)
          DebridActionItem(
            icon: Icons.shuffle_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Play Random',
            subtitle: 'Start a random file from this collection',
            pillLabel: 'Random',
            onTap: () => run('play_random'),
          ),
        DebridActionItem(
          icon: Icons.folder_open_rounded,
          color: const Color(0xFF818CF8),
          title: 'View Files',
          subtitle: 'Browse folder contents',
          pillLabel: 'Files',
          onTap: () => run('view_files'),
        ),
        DebridActionItem(
          icon: isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
          color: const Color(0xFFFFD700),
          title: isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
          subtitle: isFavorited
              ? 'Remove from your favorites list'
              : 'Add to your favorites list',
          pillLabel: 'Favorite',
          onTap: () => run('favorite'),
        ),
        if (hasProgress)
          DebridActionItem(
            icon: Icons.replay_rounded,
            color: const Color(0xFF60A5FA),
            title: 'Clear Progress',
            subtitle: 'Reset playback progress',
            onTap: () => run('clear_progress'),
          ),
        DebridActionItem(
          icon: Icons.delete_outline_rounded,
          color: app.home.danger,
          title: 'Delete',
          subtitle: 'Remove from playlist',
          onTap: () => run('delete'),
        ),
      ],
    );
  }

  Future<void> handlePlaylistMenuChoice(
    String choice,
    Map<String, dynamic> item,
    bool isFavorited,
  ) async {
    if (!_deps.mounted()) return;
    final context = _deps.context();
    switch (choice) {
      case 'play':
        playPlaylistItem(item);
        break;
      case 'play_random':
        playPlaylistItem(item, playRandom: true);
        break;
      case 'view_files':
        await Navigator.of(context).push(
          // Both doors are themed now (Search always was, Playlist since
          // phase two), so this screen resolves the same palette either way —
          // which is what the freeze was here to guarantee while they
          // disagreed.
          MaterialPageRoute(
            builder: (_) => PlaylistContentViewScreen(playlistItem: item),
          ),
        );
        // Progress / poster may have changed while browsing.
        _deps.reload();
        break;
      case 'favorite':
        await HomePlaylistRepository.setFavorite(item, !isFavorited);
        HapticFeedback.mediumImpact();
        _deps.reload();
        break;
      case 'clear_progress':
        // Empty (not 'Unknown') fallback so a null-titled item clears nothing
        // instead of fuzzy-matching the literal word 'unknown' and wiping an
        // unrelated item's resume point — matches the Home section.
        await HomePlaylistRepository.clearProgress(
          title: (item['title'] as String?) ?? '',
        );
        HapticFeedback.mediumImpact();
        _deps.reload();
        break;
      case 'delete':
        await confirmDeletePlaylistItem(item);
        break;
    }
  }

  Future<void> playPlaylistItem(
    Map<String, dynamic> item, {
    bool playRandom = false,
  }) async {
    if (playlistLaunching) return;
    playlistLaunching = true;
    try {
      await _deps.play(_deps.context(), item, playRandom: playRandom);
    } catch (e) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
    } finally {
      if (_deps.mounted()) playlistLaunching = false;
    }
  }

  Future<void> confirmDeletePlaylistItem(Map<String, dynamic> item) async {
    final context = _deps.context();
    final title = (item['title'] as String?) ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Remove "$title" from your playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppThemeScope.of(dialogContext).home.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final dedupeKey = HomePlaylistRepository.dedupeKey(item);
      await HomePlaylistRepository.removeByKey(dedupeKey);
      HapticFeedback.mediumImpact();
      _deps.reload();
    }
  }
}
