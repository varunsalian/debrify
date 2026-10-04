import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_simkl_descriptions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_simkl_status_row.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_action_row.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_group_label.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_rating_strip.dart';
import 'package:debrify/features/merged_detail/presentation/merged_tracker_sheet_header.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:flutter/material.dart';

/// Simkl's sheet — the same job as [_TraktSheet], deliberately not sharing a
/// type with it (Trakt and Simkl stay independent everywhere in this screen).
///
/// A title sits in at most one of five lists. Turning on a different switch
/// moves it; turning off the active switch removes it from the Simkl library.
class _SimklSheet extends StatefulWidget {
  final String title;
  final bool isTelevision;
  final SimklTitleStatus? status;
  final List<SimklMenuOption> Function(SimklTitleStatus? status) optionsFor;
  final Future<void> Function(SimklItemMenuAction action) onAction;
  final Future<void> Function(int rating)? onRate;
  final Future<SimklTitleStatus?> Function()? statusLoader;
  final void Function(SimklTitleStatus? status) onChanged;

  const _SimklSheet({
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
  State<_SimklSheet> createState() => _SimklSheetState();
}

class _SimklSheetState extends State<_SimklSheet> {
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
    final clearProgress = opt(SimklItemMenuAction.clearWatchProgress);
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
        MergedSimklStatusRow(
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
            MergedTrackerSheetHeader(
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
                      const MergedSheetGroupLabel('Status'),
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
                      const MergedSheetGroupLabel('Rating'),
                      MergedSheetRatingStrip(
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
                    if (clearProgress != null)
                      MergedSheetActionRow(
                        icon: clearProgress.icon,
                        label: clearProgress.label,
                        description:
                            MergedDetailSimklDescriptions.descriptionForSimkl(
                              clearProgress.action,
                            ),
                        onTap: () =>
                            _run(() => widget.onAction(clearProgress.action)),
                      ),
                    if (removeCw != null) ...[
                      const MergedSheetGroupLabel('Playback'),
                      MergedSheetActionRow(
                        icon: removeCw.icon,
                        label: removeCw.label,
                        description:
                            MergedDetailSimklDescriptions.descriptionForSimkl(
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

typedef MergedSimklSheet = _SimklSheet;

const mergedSimklSheetConstructor = _SimklSheet.new;
