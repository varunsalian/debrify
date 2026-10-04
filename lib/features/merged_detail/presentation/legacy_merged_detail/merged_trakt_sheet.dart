import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/merged_detail_action_descriptions.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_action_row.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_group_label.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_rating_strip.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_switch_row.dart';
import 'package:debrify/features/merged_detail/presentation/merged_tracker_sheet_header.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

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
class _TraktSheet extends StatefulWidget {
  final String title;
  final bool isTelevision;
  final TraktTitleStatus? status;
  final List<TraktMenuOption> Function(TraktTitleStatus? status) optionsFor;
  final Future<void> Function(TraktItemMenuAction action) onAction;
  final Future<void> Function(int rating)? onRate;
  final Future<TraktTitleStatus?> Function()? statusLoader;
  final void Function(TraktTitleStatus? status) onChanged;

  const _TraktSheet({
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
  State<_TraktSheet> createState() => _TraktSheetState();
}

class _TraktSheetState extends State<_TraktSheet> {
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
    final clearProgress = opt(TraktItemMenuAction.clearTraktProgress);
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
        MergedSheetSwitchRow(
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
        MergedSheetSwitchRow(
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
        MergedSheetSwitchRow(
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
            MergedTrackerSheetHeader(
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
                      const MergedSheetGroupLabel('Your library'),
                      ...libraryRows,
                    ],
                    if (watchedIsAmbiguous) ...[
                      const MergedSheetGroupLabel('History'),
                      MergedSheetActionRow(
                        icon: markWatched.icon,
                        label: markWatched.label,
                        description:
                            MergedDetailActionDescriptions.descriptionFor(
                              markWatched.action,
                            ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(markWatched.action)),
                      ),
                      MergedSheetActionRow(
                        icon: markUnwatched.icon,
                        label: markUnwatched.label,
                        description:
                            MergedDetailActionDescriptions.descriptionFor(
                              markUnwatched.action,
                            ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(markUnwatched.action)),
                      ),
                    ],
                    if (clearProgress != null)
                      MergedSheetActionRow(
                        icon: clearProgress.icon,
                        label: clearProgress.label,
                        description:
                            MergedDetailActionDescriptions.descriptionFor(
                              clearProgress.action,
                            ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(clearProgress.action)),
                      ),
                    if (canRate) ...[
                      const MergedSheetGroupLabel('Rating'),
                      MergedSheetRatingStrip(
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
                      const MergedSheetGroupLabel('Lists'),
                      MergedSheetActionRow(
                        icon: addToList.icon,
                        label: addToList.label,
                        description:
                            MergedDetailActionDescriptions.descriptionFor(
                              addToList.action,
                            ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(addToList.action)),
                      ),
                    ],
                    if (removePlayback != null) ...[
                      const MergedSheetGroupLabel('Playback'),
                      MergedSheetActionRow(
                        icon: removePlayback.icon,
                        label: removePlayback.label,
                        description:
                            MergedDetailActionDescriptions.descriptionFor(
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

typedef MergedTraktSheet = _TraktSheet;

const mergedTraktSheetConstructor = _TraktSheet.new;
