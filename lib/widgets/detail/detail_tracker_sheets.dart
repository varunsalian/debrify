// Extracted verbatim from lib/screens/merged_series_detail_screen.dart
// (that screen's private presentational tail). Behaviour is unchanged; the
// only edits are the renames that make these public and the parameters that
// replace the host's private members.

import 'package:flutter/material.dart';

import '../../services/simkl/simkl_menu_helpers.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/trakt/trakt_service.dart';
import '../tracker_brand_marks.dart';
import '../trakt/trakt_menu_helpers.dart';

/// Human-readable description of each quick action, shown in the More menu.
String detailTraktActionDescription(TraktItemMenuAction a) {
  switch (a) {
    case TraktItemMenuAction.selectSource:
      return 'Pin a specific torrent or file as this title\'s source so every '
          'play uses it — no re-searching each time. Change or clear it here.';
    case TraktItemMenuAction.addToStremioTv:
      return 'Add this to your Stremio TV channel so it plays in your '
          'always-on rotation alongside your other picks.';
    case TraktItemMenuAction.playRandomEpisode:
      return 'Skip the browsing and jump straight into a random episode from '
          'this series — handy for background or comfort watching.';
    case TraktItemMenuAction.searchPacks:
      return 'Open a search for full-season and complete-series packs, then '
          'do whatever you want with a result — play it, download it, and more.';
    case TraktItemMenuAction.addToWatchlist:
      return 'Save this to your Trakt watchlist so you can find it later, '
          'synced across every device signed into your account.';
    case TraktItemMenuAction.removeFromWatchlist:
      return 'Take this off your Trakt watchlist — it won\'t appear in your '
          '"to watch" list anymore.';
    case TraktItemMenuAction.addToCollection:
      return 'Mark this as part of your Trakt collection — your library of '
          'everything you own or keep track of.';
    case TraktItemMenuAction.removeFromCollection:
      return 'Remove this from your Trakt collection.';
    case TraktItemMenuAction.markWatched:
      return 'Mark every episode of this title as watched on Trakt and sync '
          'that history across all your devices.';
    case TraktItemMenuAction.markUnwatched:
      return 'Clear this title from your Trakt history so it counts as '
          'unwatched again and can resurface in "up next".';
    case TraktItemMenuAction.rate:
      return 'Give this a 1–10 rating on Trakt. Your ratings sync everywhere '
          'and help shape your recommendations.';
    case TraktItemMenuAction.removeRating:
      return 'Remove the rating you previously gave this on Trakt.';
    case TraktItemMenuAction.addToList:
      return 'Add this to one of your custom Trakt lists — like "Weekend", '
          '"With friends" or anything you\'ve made.';
    case TraktItemMenuAction.removeFromList:
      return 'Remove this from one of your custom Trakt lists.';
    case TraktItemMenuAction.removeFromPlayback:
      return 'Remove this from Continue Watching so it stops showing on your '
          'home rows and resume list.';
    case TraktItemMenuAction.removeFromTraktPlayback:
      return 'Delete this title\'s playback progress (and watch history) on '
          'Trakt so it leaves the Trakt Continue Watching rows.';
  }
}

/// Human-readable description of each Simkl quick action, shown in its
/// own More menu — mirrors [detailTraktActionDescription].
String detailSimklActionDescription(SimklItemMenuAction a) {
  switch (a) {
    case SimklItemMenuAction.moveToPlanToWatch:
      return 'Move this to your Simkl "Plan to Watch" list — a personal '
          'watch queue synced across every device signed into your account.';
    case SimklItemMenuAction.moveToWatching:
      return 'Mark this as currently watching on Simkl, without changing '
          'any episode watched state.';
    case SimklItemMenuAction.moveToOnHold:
      return 'Pause this on Simkl — keeps it out of Plan to Watch and '
          'Watching until you\'re ready to pick it back up.';
    case SimklItemMenuAction.moveToCompleted:
      return 'Mark this completed on Simkl and sync that history across '
          'all your devices.';
    case SimklItemMenuAction.moveToDropped:
      return 'Mark this dropped on Simkl so it stops showing up as '
          'something you\'re meaning to finish.';
    case SimklItemMenuAction.removeFromList:
      return 'Remove this title from your Simkl library, including its '
          'active status, watched history, rating and saved playback progress.';
    case SimklItemMenuAction.removeFromContinueWatching:
      return 'Take this off your Simkl Continue Watching rows. A movie just '
          'clears its paused position; a series is moved to On Hold so its '
          'next episode doesn\'t re-surface as an "up next" card.';
    case SimklItemMenuAction.rate:
      return 'Give this a 1–10 rating on Simkl.';
    case SimklItemMenuAction.removeRating:
      return 'Remove the rating you previously gave this on Simkl.';
  }
}

/// The "More" quick-actions menu — a labelled sheet with an icon, name and a
/// one-line description for every action, so users know what each one does.
class DetailQuickActionsMenu extends StatelessWidget {
  final String title;
  final List<TraktMenuOption> options;
  final bool isTelevision;
  final void Function(TraktItemMenuAction action) onSelected;

  const DetailQuickActionsMenu({
    super.key,
    required this.title,
    required this.options,
    required this.isTelevision,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Standard sheet chrome (background + drag handle) is provided by
    // showModalBottomSheet — this widget is just the header + clean list, so it
    // reads the same as the per-episode ⋮ menu.
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'More',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: options.length,
                itemBuilder: (context, i) => _item(options[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(TraktMenuOption o, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: isTelevision && index == 0,
        // The default focus overlay is invisible on the dark sheet — make the
        // DPAD cursor obvious.
        focusColor: Colors.white.withValues(alpha: 0.12),
        onTap: () => onSelected(o.action),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 18, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(o.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      o.label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detailTraktActionDescription(o.action),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
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
    );
  }
}

/// Shared chrome for a tracker sheet: the brand lockup, the title it applies
/// to, and a hairline progress line while an action is in flight.
///
/// Only the chrome is shared — the two sheets' bodies stay fully independent,
/// per the "no shared type between the trackers" rule this screen follows.
class DetailTrackerSheetHeader extends StatelessWidget {
  final Widget mark;
  final String brand;
  final String title;
  final Color accent;
  final bool busy;

  const DetailTrackerSheetHeader({
    super.key,
    required this.mark,
    required this.brand,
    required this.title,
    required this.accent,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.centerRight,
              colors: [accent.withValues(alpha: 0.18), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              mark,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      brand,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: busy
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: accent,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                )
              : Container(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ],
    );
  }
}

/// Section label inside a tracker sheet.
class DetailSheetGroupLabel extends StatelessWidget {
  final String label;
  const DetailSheetGroupLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.38),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    ),
  );
}

/// A relationship the tracker either holds or doesn't — rendered as a switch
/// so the current state is readable without parsing an "Add…"/"Remove…" verb.
class DetailSheetSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Color accent;
  final bool autofocus;
  final VoidCallback onTap;

  const DetailSheetSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: autofocus,
        focusColor: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: value ? accent : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // A drawn switch rather than a Material Switch: this is a
              // command that round-trips to an API, so it must not animate to
              // the new position before the call lands — the parent re-reads
              // the status and rebuilds with the truth.
              Container(
                width: 42,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? accent : Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain icon + label + description row, for actions that aren't a state
/// (list management, playback removal).
class DetailSheetActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color? color;
  final bool autofocus;
  final VoidCallback onTap;

  const DetailSheetActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.color,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: autofocus,
        focusColor: Colors.white.withValues(alpha: 0.12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 21, color: tint),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: tint,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
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
    );
  }
}

/// The 1–10 rating strip. Ten focusable cells beat a modal dialog on both
/// inputs: one tap on touch, a LEFT/RIGHT run and OK on a remote.
class DetailSheetRatingStrip extends StatelessWidget {
  final int? rating;
  final Color accent;
  final Color onAccent;
  final void Function(int rating) onRate;
  final VoidCallback? onClear;

  /// Puts the DPAD cursor on the current score (or 1 when unrated) — used when
  /// the strip is the first thing in the sheet.
  final bool autofocus;

  const DetailSheetRatingStrip({
    super.key,
    required this.rating,
    required this.accent,
    required this.onAccent,
    required this.onRate,
    this.onClear,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final current = rating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 10; i++) ...[
                if (i > 1) const SizedBox(width: 5),
                Expanded(
                  child: Material(
                    color: current == null || i > current
                        ? Colors.white.withValues(alpha: 0.07)
                        : (i == current
                              ? accent
                              : accent.withValues(alpha: 0.22)),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      autofocus: autofocus && i == (current ?? 1),
                      borderRadius: BorderRadius.circular(8),
                      focusColor: Colors.white.withValues(alpha: 0.18),
                      onTap: () => onRate(i),
                      child: SizedBox(
                        height: 32,
                        child: Center(
                          child: Text(
                            '$i',
                            style: TextStyle(
                              color: current != null && i == current
                                  ? onAccent
                                  : Colors.white.withValues(
                                      alpha: current != null && i < current
                                          ? 0.85
                                          : 0.5,
                                    ),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                current != null ? 'Rated $current/10' : 'Not rated',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              if (onClear != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    focusColor: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        'Clear rating',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Trakt's sheet.
///
/// Takes the same option list the old menu did — so every availability rule
/// (connected? has an IMDb id? on a Trakt Continue Watching row?) still lives
/// in `buildTraktAddOnlyMenuOptions` — but renders the add/remove pairs as
/// switches, since each pair is really one on/off relationship.
///
/// Stays open across actions: after each one it re-reads the live status via
/// [statusLoader] and rebuilds its options from it, so the switches always
/// show what Trakt actually holds rather than an optimistic guess.
class DetailTraktSheet extends StatefulWidget {
  final String title;
  final bool isTelevision;
  final TraktTitleStatus? status;
  final List<TraktMenuOption> Function(TraktTitleStatus? status) optionsFor;
  final Future<void> Function(TraktItemMenuAction action) onAction;
  final Future<void> Function(int rating)? onRate;
  final Future<TraktTitleStatus?> Function()? statusLoader;
  final void Function(TraktTitleStatus? status) onChanged;

  const DetailTraktSheet({
    super.key,
    required this.title,
    required this.isTelevision,
    required this.status,
    required this.optionsFor,
    required this.onAction,
    required this.onRate,
    required this.statusLoader,
    required this.onChanged,
  });

  @override
  State<DetailTraktSheet> createState() => _DetailTraktSheetState();
}

class _DetailTraktSheetState extends State<DetailTraktSheet> {
  late TraktTitleStatus? _status = widget.status;
  bool _busy = false;

  /// Runs one action, then re-reads the status so the sheet (and the pill
  /// behind it, via [onChanged]) reflect the result. Serialised: a second tap
  /// while a call is in flight is dropped rather than racing it.
  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      final loader = widget.statusLoader;
      if (loader != null) {
        final fresh = await loader();
        // Null means "couldn't be trusted" (disconnected, or the library fetch
        // failed), NOT "nothing tracked" — both services document that, and a
        // genuine empty answer comes back as a non-null all-false status. So
        // keep showing the last known state rather than fabricating one.
        if (fresh == null) return;
        // Publish first: the sheet may already be gone (dismissed mid-call),
        // and the screen behind it still needs the result for its pill.
        widget.onChanged(fresh);
        if (!mounted) return;
        setState(() => _status = fresh);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.optionsFor(_status);
    TraktMenuOption? opt(TraktItemMenuAction a) {
      for (final o in options) {
        if (o.action == a) return o;
      }
      return null;
    }

    final watchlistOn = opt(TraktItemMenuAction.removeFromWatchlist);
    final watchlistOff = opt(TraktItemMenuAction.addToWatchlist);
    final collectionOn = opt(TraktItemMenuAction.removeFromCollection);
    final collectionOff = opt(TraktItemMenuAction.addToCollection);
    final markWatched = opt(TraktItemMenuAction.markWatched);
    final markUnwatched = opt(TraktItemMenuAction.markUnwatched);
    // Only `addToList` is ever emitted (and `handleTraktMenuAction` returns
    // early on removeFromList — there's no context for *which* list), so this
    // section is add-only by design.
    final addToList = opt(TraktItemMenuAction.addToList);
    final removePlayback = opt(TraktItemMenuAction.removeFromTraktPlayback);
    final canRate = opt(TraktItemMenuAction.rate) != null;
    final canUnrate = opt(TraktItemMenuAction.removeRating) != null;

    // A series' whole-title watched state is unknown (the episode list owns
    // it), so Trakt offers BOTH mark actions — that can't be a switch, and
    // shows as two explicit commands instead.
    final watchedIsAmbiguous = markWatched != null && markUnwatched != null;

    // TV: whichever row renders first takes the cursor. Which sections exist
    // depends on the live status, so this is claimed in build order rather
    // than hard-coded to one row.
    var focusClaimed = false;
    bool claimFocus() {
      if (!widget.isTelevision || focusClaimed) return false;
      return focusClaimed = true;
    }

    final libraryRows = <Widget>[
      if (watchlistOn != null || watchlistOff != null)
        DetailSheetSwitchRow(
          icon: Icons.bookmark_rounded,
          label: 'Watchlist',
          subtitle: 'Synced to every device on your Trakt account',
          value: watchlistOn != null,
          accent: kTraktRed,
          autofocus: claimFocus(),
          onTap: () => _run(
            () => widget.onAction((watchlistOn ?? watchlistOff)!.action),
          ),
        ),
      if (collectionOn != null || collectionOff != null)
        DetailSheetSwitchRow(
          icon: Icons.video_library_rounded,
          label: 'Collection',
          subtitle: 'Your library of everything you own or keep track of',
          value: collectionOn != null,
          accent: kTraktRed,
          autofocus: claimFocus(),
          onTap: () => _run(
            () => widget.onAction((collectionOn ?? collectionOff)!.action),
          ),
        ),
      if (!watchedIsAmbiguous && (markWatched != null || markUnwatched != null))
        DetailSheetSwitchRow(
          icon: Icons.visibility_rounded,
          label: 'Watched',
          subtitle: 'Syncs your history across all your devices',
          value: markUnwatched != null,
          accent: kTraktRed,
          autofocus: claimFocus(),
          onTap: () => _run(
            () => widget.onAction((markUnwatched ?? markWatched)!.action),
          ),
        ),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DetailTrackerSheetHeader(
              mark: const TraktMark(size: 30),
              brand: 'Trakt',
              title: widget.title,
              accent: kTraktRed,
              busy: _busy,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (libraryRows.isNotEmpty) ...[
                      const DetailSheetGroupLabel('Your library'),
                      ...libraryRows,
                    ],
                    if (watchedIsAmbiguous) ...[
                      const DetailSheetGroupLabel('History'),
                      DetailSheetActionRow(
                        icon: markWatched.icon,
                        label: markWatched.label,
                        description: detailTraktActionDescription(
                          markWatched.action,
                        ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(markWatched.action)),
                      ),
                      DetailSheetActionRow(
                        icon: markUnwatched.icon,
                        label: markUnwatched.label,
                        description: detailTraktActionDescription(
                          markUnwatched.action,
                        ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(markUnwatched.action)),
                      ),
                    ],
                    if (canRate) ...[
                      const DetailSheetGroupLabel('Rating'),
                      DetailSheetRatingStrip(
                        rating: _status?.rating,
                        accent: kTraktRed,
                        onAccent: Colors.white,
                        autofocus: claimFocus(),
                        onRate: (r) => _run(() async {
                          final rate = widget.onRate;
                          // No inline-rate callback wired (e.g. the IPTV
                          // caller) — fall back to the tracker's own dialog.
                          if (rate == null) {
                            await widget.onAction(TraktItemMenuAction.rate);
                          } else {
                            await rate(r);
                          }
                        }),
                        onClear: canUnrate
                            ? () => _run(
                                () => widget.onAction(
                                  TraktItemMenuAction.removeRating,
                                ),
                              )
                            : null,
                      ),
                    ],
                    if (addToList != null) ...[
                      const DetailSheetGroupLabel('Lists'),
                      DetailSheetActionRow(
                        icon: addToList.icon,
                        label: addToList.label,
                        description: detailTraktActionDescription(
                          addToList.action,
                        ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(addToList.action)),
                      ),
                    ],
                    if (removePlayback != null) ...[
                      const DetailSheetGroupLabel('Playback'),
                      DetailSheetActionRow(
                        icon: removePlayback.icon,
                        label: removePlayback.label,
                        description: detailTraktActionDescription(
                          removePlayback.action,
                        ),
                        color: const Color(0xFFFF8B8B),
                        autofocus: claimFocus(),
                        // Closes the sheet: whether this title is still on a
                        // Trakt Continue Watching row was decided when the
                        // screen opened, so the row can't refresh itself.
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onAction(removePlayback.action);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simkl's sheet — the same job as [DetailTraktSheet], deliberately not sharing a
/// type with it (Trakt and Simkl stay independent everywhere in this screen).
///
/// A title sits in at most one of five lists. Turning on a different switch
/// moves it; turning off the active switch removes it from the Simkl library.
class DetailSimklSheet extends StatefulWidget {
  final String title;
  final bool isTelevision;
  final SimklTitleStatus? status;
  final List<SimklMenuOption> Function(SimklTitleStatus? status) optionsFor;
  final Future<void> Function(SimklItemMenuAction action) onAction;
  final Future<void> Function(int rating)? onRate;
  final Future<SimklTitleStatus?> Function()? statusLoader;
  final void Function(SimklTitleStatus? status) onChanged;

  const DetailSimklSheet({
    super.key,
    required this.title,
    required this.isTelevision,
    required this.status,
    required this.optionsFor,
    required this.onAction,
    required this.onRate,
    required this.statusLoader,
    required this.onChanged,
  });

  @override
  State<DetailSimklSheet> createState() => _DetailSimklSheetState();
}

class _DetailSimklSheetState extends State<DetailSimklSheet> {
  late SimklTitleStatus? _status = widget.status;
  bool _busy = false;

  /// Simkl's five lists, in the order the service presents them.
  static const _statuses = <(String, String, SimklItemMenuAction, IconData)>[
    (
      'plantowatch',
      'Plan to Watch',
      SimklItemMenuAction.moveToPlanToWatch,
      Icons.bookmark_add_rounded,
    ),
    (
      'watching',
      'Watching',
      SimklItemMenuAction.moveToWatching,
      Icons.visibility_rounded,
    ),
    (
      'hold',
      'On Hold',
      SimklItemMenuAction.moveToOnHold,
      Icons.pause_circle_rounded,
    ),
    (
      'completed',
      'Completed',
      SimklItemMenuAction.moveToCompleted,
      Icons.check_circle_rounded,
    ),
    (
      'dropped',
      'Dropped',
      SimklItemMenuAction.moveToDropped,
      Icons.cancel_rounded,
    ),
  ];

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      final loader = widget.statusLoader;
      if (loader != null) {
        final fresh = await loader();
        // Null means "couldn't be trusted" (disconnected, or the library fetch
        // failed), NOT "nothing tracked" — both services document that, and a
        // genuine empty answer comes back as a non-null all-false status. So
        // keep showing the last known state rather than fabricating one.
        if (fresh == null) return;
        // Publish first: the sheet may already be gone (dismissed mid-call),
        // and the screen behind it still needs the result for its pill.
        widget.onChanged(fresh);
        if (!mounted) return;
        setState(() => _status = fresh);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.optionsFor(_status);
    SimklMenuOption? opt(SimklItemMenuAction a) {
      for (final o in options) {
        if (o.action == a) return o;
      }
      return null;
    }

    final current = _status?.currentStatus;
    final canRemove = opt(SimklItemMenuAction.removeFromList) != null;
    final removeCw = opt(SimklItemMenuAction.removeFromContinueWatching);
    final canRate = opt(SimklItemMenuAction.rate) != null;
    final canUnrate = opt(SimklItemMenuAction.removeRating) != null;

    // A status row is offered when its move action is available, and the
    // current one is always shown even though the builder omits it (there's
    // nowhere to move it to). Movies therefore keep hiding Watching and On
    // Hold — Simkl treats them as a single session — with no rule duplicated
    // here: it falls out of what the builder offered.
    final visible = [
      for (final (value, label, action, icon) in _statuses)
        if (opt(action) != null || value == current)
          (value, label, action, icon),
    ];
    // TV: start on the current status when there is one — that's where the
    // user's attention already is, and moving from it is the whole point.
    final currentIndex = visible.indexWhere((s) => s.$1 == current);
    final focusIndex = currentIndex >= 0 ? currentIndex : 0;
    final rows = <Widget>[
      for (final (i, (value, label, action, icon)) in visible.indexed)
        DetailSimklStatusRow(
          icon: icon,
          label: label,
          selected: value == current,
          autofocus: widget.isTelevision && i == focusIndex,
          // These switches form one exclusive group. Turning another one on
          // moves the title; turning the active one off removes it entirely.
          // Keep every row focusable so a successful move doesn't strand DPAD.
          onTap: value == current
              ? (canRemove
                    ? () => _run(
                        () =>
                            widget.onAction(SimklItemMenuAction.removeFromList),
                      )
                    : () {})
              : () => _run(() => widget.onAction(action)),
        ),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DetailTrackerSheetHeader(
              mark: const SimklMark(size: 30),
              brand: 'Simkl',
              title: widget.title,
              accent: kSimklCyan,
              busy: _busy,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isNotEmpty) ...[
                      const DetailSheetGroupLabel('Status'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: rows,
                        ),
                      ),
                    ],
                    if (canRate) ...[
                      const DetailSheetGroupLabel('Rating'),
                      DetailSheetRatingStrip(
                        rating: _status?.rating,
                        accent: kSimklCyan,
                        onAccent: const Color(0xFF04262C),
                        autofocus: widget.isTelevision && rows.isEmpty,
                        onRate: (r) => _run(() async {
                          final rate = widget.onRate;
                          if (rate == null) {
                            await widget.onAction(SimklItemMenuAction.rate);
                          } else {
                            await rate(r);
                          }
                        }),
                        onClear: canUnrate
                            ? () => _run(
                                () => widget.onAction(
                                  SimklItemMenuAction.removeRating,
                                ),
                              )
                            : null,
                      ),
                    ],
                    if (removeCw != null) ...[
                      const DetailSheetGroupLabel('Playback'),
                      DetailSheetActionRow(
                        icon: removeCw.icon,
                        label: removeCw.label,
                        description: detailSimklActionDescription(
                          removeCw.action,
                        ),
                        color: const Color(0xFFFF8B8B),
                        autofocus:
                            widget.isTelevision && rows.isEmpty && !canRate,
                        // Closes for the same reason as Trakt's: whether the
                        // title has a paused session was decided when the
                        // screen opened.
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onAction(removeCw.action);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of Simkl's five mutually-exclusive list switches. The whole row is the
/// DPAD stop; the nested switch is excluded from focus so TV navigation still
/// costs one press per status.
class DetailSimklStatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool autofocus;

  /// Never null so every row remains focusable after a state transition.
  final VoidCallback onTap;

  const DetailSimklStatusRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(11);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? kSimklCyan.withValues(alpha: 0.13)
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          autofocus: autofocus,
          borderRadius: radius,
          focusColor: Colors.white.withValues(alpha: 0.12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? kSimklCyan.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? kSimklCyan
                      : Colors.white.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? kSimklCyan : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ExcludeFocus(
                  child: Switch.adaptive(
                    value: selected,
                    activeThumbColor: kSimklCyan,
                    activeTrackColor: kSimklCyan.withValues(alpha: 0.42),
                    onChanged: (_) => onTap(),
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
