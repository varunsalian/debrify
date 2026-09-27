import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../widgets/home/cw_card_menu.dart';
import 'home_stage_rows.dart';

/// One view's hold/menu interaction. Row actions and focus nodes are borrowed.
/// The active view/profile guard rejects delayed preferences and modal results.
class HomeContinueWatchingActions {
  bool _busy = false;

  Future<void> open({
    required BuildContext context,
    required HomeContinuationRow row,
    required StremioMeta item,
    required bool pikpakOnly,
    required bool Function() isTelevision,
    required bool Function() isCurrent,
    required Future<bool> Function() readHoldToQuickPlay,
    required VoidCallback refocusAfterRemoval,
  }) async {
    if (_busy || !context.mounted || !isCurrent()) return;
    _busy = true;
    final isSeries = item.type == 'series';
    final playActionAvailable =
        row.kind == HomeContinuationKind.iptv || !pikpakOnly;
    final removeActionAvailable = row.canRemove?.call(item) ?? true;
    if (!playActionAvailable && !removeActionAvailable) {
      _busy = false;
      return;
    }
    // IPTV series use their primary action to open the series page; that is
    // still useful in the menu, but it is not the immediate playback this
    // preference promises.
    final quickPlayAvailable =
        playActionAvailable &&
        !(row.kind == HomeContinuationKind.iptv && isSeries);
    try {
      final holdToQuickPlay = await readHoldToQuickPlay();
      if (!context.mounted || !isCurrent()) return;
      if (holdToQuickPlay && quickPlayAvailable) {
        row.onQuickPlay(item);
        return;
      }
    } catch (_) {
      // A preference read must never take the existing action menu away.
    } finally {
      // The dialog path takes ownership of this guard below. Direct Quick Play
      // and failed preference reads release it here.
      _busy = false;
    }
    if (!context.mounted || !isCurrent()) return;
    _busy = true;
    // An IPTV series card routes to its Xtream series page rather than playing
    // outright (see the IPTV row action) — so name the action for what it does.
    final playLabel = (row.kind == HomeContinuationKind.iptv && isSeries)
        ? 'Open series'
        : 'Play';
    final String playDescription;
    final String removeDescription;
    switch (row.kind) {
      case HomeContinuationKind.local:
        playDescription = isSeries
            ? 'Jump back into the episode you stopped on.'
            : 'Resume from where you left off.';
        removeDescription =
            'Takes it off this row and clears the position saved on this '
            'device.';
      case HomeContinuationKind.trakt:
        playDescription = isSeries
            ? 'Jump back into the episode you stopped on.'
            : 'Resume from where you left off.';
        removeDescription =
            'Deletes this title\'s playback progress (and watch history) on '
            'Trakt, so it leaves the Trakt rows everywhere.';
      case HomeContinuationKind.simkl:
        playDescription = isSeries
            ? 'Jump back into the episode you stopped on.'
            : 'Resume from where you left off.';
        removeDescription = isSeries
            ? 'Moves the show to On Hold on Simkl and clears the paused '
                  'position, so it stops resurfacing as up next.'
            : 'Clears this movie\'s paused position on Simkl.';
      case HomeContinuationKind.mdblist:
        playDescription = isSeries
            ? 'Jump into the paused or next unwatched episode from MDBList.'
            : 'Resume from the position saved on MDBList.';
        removeDescription =
            'Clears this paused playback position from MDBList.';
      case HomeContinuationKind.iptv:
        playDescription = isSeries
            ? 'Open the series and pick up where you left off.'
            : 'Resume from where you left off.';
        removeDescription = isSeries
            ? 'Clears every watched episode of this series from your IPTV '
                  'history.'
            : 'Clears this item from your IPTV watch history and forgets its '
                  'position.';
    }

    final episode = row.episodeOf(item);
    CwCardAction? action;
    try {
      action = await showCwCardMenu(
        context,
        title: item.name,
        isTelevision: isTelevision(),
        posterUrl: item.poster,
        subtitle: [row.title, if (episode != null) episode].join('  ·  '),
        // Mirrors the card's own long-press-to-play gate: PikPak-only setups
        // have no quick play, so the menu offers the removal alone.
        showPlay: playActionAvailable,
        showRemove: removeActionAvailable,
        playLabel: playLabel,
        playDescription: playDescription,
        removeDescription: removeDescription,
      );
    } finally {
      _busy = false;
    }
    if (!context.mounted || !isCurrent() || action == null) return;
    switch (action) {
      case CwCardAction.play:
        row.onQuickPlay(item);
      case CwCardAction.remove:
        await row.onRemove(item);
        if (!context.mounted || !isCurrent()) return;
        refocusAfterRemoval();
    }
  }
}
