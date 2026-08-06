import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import 'simkl_service.dart';

/// Actions available in the Simkl episode overflow menu.
enum SimklEpisodeMenuAction { markWatched, markUnwatched, rate }

/// Actions available in the Simkl item quick-action strip.
///
/// Deliberately smaller than [TraktItemMenuAction]: Simkl has no
/// Collection/Recommendations concept and no custom-lists API yet, and no
/// "remove from list" endpoint — only moving between the 5 watchlist states,
/// which is why these are `moveToX` actions rather than Trakt-style
/// add/remove toggles.
enum SimklItemMenuAction {
  moveToPlanToWatch,
  moveToWatching,
  moveToOnHold,
  moveToCompleted,
  moveToDropped,
  removeFromContinueWatching,
  rate,
  removeRating,
}

/// Shows a 1-10 rating dialog. Returns the selected rating or null.
///
/// Duplicated from `trakt_menu_helpers.dart`'s `showTraktRatingDialog` rather
/// than shared — that dialog has zero Trakt-specific logic, but per the
/// established "full independence over shared abstraction" rule for this
/// integration, Simkl gets its own copy so nothing here can regress Trakt's.
Future<int?> showSimklRatingDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rate_rounded,
                    color: Color(0xFF22D3EE),
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Rate this item',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: List.generate(10, (i) {
                  final rating = i + 1;
                  return SizedBox(
                    width: 52,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: const Color(0xFF22D3EE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(rating),
                      child: Text(
                        '$rating',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Handles a Simkl menu action for a given item. Shows snackbar feedback.
Future<void> handleSimklMenuAction(
  BuildContext context,
  StremioMeta item,
  SimklItemMenuAction action, {
  /// Skips the rating dialog for [SimklItemMenuAction.rate] and submits this
  /// value directly — mirrors `handleTraktMenuAction`'s [presetRating], for
  /// the merged detail sheet's inline 1–10 strip.
  int? presetRating,
}) async {
  final simklService = SimklService.instance;
  final imdbId = item.effectiveImdbId ?? item.id;
  final type = item.type;
  bool success = false;
  String actionLabel = '';

  switch (action) {
    case SimklItemMenuAction.moveToPlanToWatch:
      actionLabel = 'Moved to Plan to Watch on Simkl';
      success = await simklService.addToList(imdbId, type, 'plantowatch');
    case SimklItemMenuAction.moveToWatching:
      actionLabel = 'Moved to Watching on Simkl';
      success = await simklService.addToList(imdbId, type, 'watching');
    case SimklItemMenuAction.moveToOnHold:
      actionLabel = 'Moved to On Hold on Simkl';
      success = await simklService.addToList(imdbId, type, 'hold');
    case SimklItemMenuAction.moveToCompleted:
      actionLabel = 'Marked Completed on Simkl';
      success = await simklService.addToList(imdbId, type, 'completed');
      // Completed/Dropped titles are NOT hidden by status (a paused session on
      // them is an active rewatch), so clearing the paused session is what takes
      // this OFF Continue Watching — fold the result in: a failed clear leaves
      // it in the row, so don't report a clean success.
      if (success) success = await simklService.deletePlaybackForImdb(imdbId);
    case SimklItemMenuAction.moveToDropped:
      actionLabel = 'Marked Dropped on Simkl';
      success = await simklService.addToList(imdbId, type, 'dropped');
      // As above — the session-clear is what removes it, so fold the result in.
      if (success) success = await simklService.deletePlaybackForImdb(imdbId);
    case SimklItemMenuAction.removeFromContinueWatching:
      if (type == 'series') {
        // A still-"watching" series shows in the paused row (its session) and
        // would also re-surface as an "up next" card. Move it to On Hold: that
        // takes it out of BOTH (the paused row is status-filtered, up-next
        // fetches only 'watching'). Best-effort clear the paused session too
        // (definitive — drops the resume position; a failure here doesn't leave
        // it in the row, so it must not flip the action to "failed").
        actionLabel = 'Removed — moved to On Hold on Simkl';
        success = await simklService.addToList(imdbId, type, 'hold');
        if (success) await simklService.deletePlaybackForImdb(imdbId);
      } else {
        // Movie: no watching/up-next status to change (a paused movie is
        // plantowatch/none, which the row still shows), so clearing the paused
        // session is what removes it — its result IS the success.
        actionLabel = 'Removed from Continue Watching';
        success = await simklService.deletePlaybackForImdb(imdbId);
      }
    case SimklItemMenuAction.rate:
      if (!context.mounted) return;
      final rating = presetRating ?? await showSimklRatingDialog(context);
      if (rating == null) return;
      actionLabel = 'Rated $rating/10 on Simkl';
      success = await simklService.rateItem(imdbId, type, rating);
    case SimklItemMenuAction.removeRating:
      actionLabel = 'Simkl Rating Removed';
      success = await simklService.removeRating(imdbId, type);
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success ? actionLabel : 'Failed: $actionLabel'),
      backgroundColor: success
          ? const Color(0xFF34D399)
          : const Color(0xFFEF4444),
      duration: const Duration(seconds: 2),
    ),
  );
}

// ── Quick actions ───────────────────────────────────────────────────────────

/// One Simkl action in the inline quick-action row. [caption] is the short
/// label shown under the icon; [label] is the full descriptive form.
class SimklMenuOption {
  final SimklItemMenuAction action;
  final IconData icon;
  final Color color;
  final String label;
  final String caption;

  const SimklMenuOption({
    required this.action,
    required this.icon,
    required this.color,
    required this.label,
    required this.caption,
  });
}

SimklItemMenuAction _statusMoveAction(String status) {
  switch (status) {
    case 'plantowatch':
      return SimklItemMenuAction.moveToPlanToWatch;
    case 'watching':
      return SimklItemMenuAction.moveToWatching;
    case 'hold':
      return SimklItemMenuAction.moveToOnHold;
    case 'completed':
      return SimklItemMenuAction.moveToCompleted;
    case 'dropped':
    default:
      return SimklItemMenuAction.moveToDropped;
  }
}

/// Structured (icon/color/label) Simkl actions for the inline quick-action
/// strip. [isSimklAuthenticated] gates the whole strip (default false, so a
/// caller can't forget the check and show a broken-looking menu to a
/// disconnected user) — Simkl's strip has no baseline app actions the way
/// Trakt's does, so there's nothing to fall back to when disconnected; it's
/// just empty.
///
/// Shows the current watchlist status (from [status]) and offers "Move to
/// X" for every OTHER applicable status, since Simkl has no toggle-off —
/// only moving between states. Watching/On Hold only apply to series
/// (Simkl's own constraint: movies are single-session).
List<SimklMenuOption> buildSimklMenuOptions({
  bool isSeries = false,
  bool isSimklAuthenticated = false,
  bool inContinueWatching = false,
  SimklTitleStatus? status,
}) {
  if (!isSimklAuthenticated) return const [];
  final String? current = status?.currentStatus;
  final int? currentRating = status?.rating;

  SimklMenuOption moveOption(String value, String label, IconData icon, Color color) {
    return SimklMenuOption(
      action: _statusMoveAction(value),
      icon: icon,
      color: color,
      label: 'Move to $label',
      caption: label,
    );
  }

  return [
    if (current != 'plantowatch')
      moveOption(
        'plantowatch',
        'Plan to Watch',
        Icons.bookmark_add_rounded,
        const Color(0xFFFBBF24),
      ),
    if (isSeries && current != 'watching')
      moveOption(
        'watching',
        'Watching',
        Icons.visibility_rounded,
        const Color(0xFF60A5FA),
      ),
    if (isSeries && current != 'hold')
      moveOption(
        'hold',
        'On Hold',
        Icons.pause_circle_rounded,
        const Color(0xFFF59E0B),
      ),
    if (current != 'completed')
      moveOption(
        'completed',
        'Completed',
        Icons.check_circle_rounded,
        const Color(0xFF34D399),
      ),
    if (current != 'dropped')
      moveOption(
        'dropped',
        'Dropped',
        Icons.cancel_rounded,
        const Color(0xFFEF4444),
      ),
    // Only when the title is actually in Continue Watching (has a paused
    // playback session) — clears that session so it leaves the CW row without
    // changing its watchlist status.
    if (inContinueWatching)
      const SimklMenuOption(
        action: SimklItemMenuAction.removeFromContinueWatching,
        icon: Icons.playlist_remove_rounded,
        color: Color(0xFFF87171),
        label: 'Remove from Continue Watching',
        caption: 'Remove',
      ),
    SimklMenuOption(
      action: SimklItemMenuAction.rate,
      icon: Icons.star_rounded,
      color: const Color(0xFF22D3EE),
      label: currentRating != null
          ? 'Change Simkl Rating ($currentRating/10)'
          : 'Rate on Simkl',
      caption: currentRating != null ? 'Rated $currentRating' : 'Rate',
    ),
    if (currentRating != null)
      const SimklMenuOption(
        action: SimklItemMenuAction.removeRating,
        icon: Icons.star_outline_rounded,
        color: Color(0xFF22D3EE),
        label: 'Remove Simkl Rating',
        caption: 'Unrate',
      ),
  ];
}
