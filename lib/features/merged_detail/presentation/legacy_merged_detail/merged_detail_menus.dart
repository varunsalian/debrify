import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_simkl_sheet.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_trakt_sheet.dart';
import 'package:debrify/features/merged_detail/presentation/merged_quick_actions_menu.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

class MergedDetailMenus {
  final MergedDetailDependencies _deps;
  MergedDetailMenus(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  void Function() get _refreshAfterPlayback => _deps.refreshAfterPlayback;
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailTrackingActions get _ta => _deps.parts.trackingActions;
  MergedDetailTrackingState get _k => _deps.parts.trackingState;

  /// The quick-actions strip to render: rebuilt against [_traktStatus] when a
  /// builder was supplied, else the static list passed in.
  List<TraktMenuOption> get menuOptions =>
      _deps.traktMenuBuilder()?.call(_k.traktStatus) ??
      _deps.traktMenuOptions();

  List<TraktMenuOption> get appMenuOptions => [
    for (final o in menuOptions)
      if (appOwnedActions.contains(o.action)) o,
  ];

  List<TraktMenuOption> get traktOnlyMenuOptions => [
    for (final o in menuOptions)
      if (!appOwnedActions.contains(o.action)) o,
  ];

  /// The Simkl quick-actions strip to render: rebuilt against [_simklStatus]
  /// when a builder was supplied, else the static list passed in.
  List<SimklMenuOption> get menuOptionsSimkl =>
      _deps.simklMenuBuilder()?.call(_k.simklStatus) ??
      _deps.simklMenuOptions();
  List<MdblistMenuOption> get menuOptionsMdblist =>
      _deps.mdblistMenuBuilder()?.call(_k.mdblistStatus) ??
      _deps.mdblistMenuOptions();

  /// Debrify's own actions, in a plain labelled list. Closes on selection —
  /// each of these leaves the sheet anyway (a picker, a search, playback).
  void showAppActionsMenu() {
    final options = appMenuOptions;
    if (options.isEmpty || _deps.onTraktAction() == null) return;
    showModalBottomSheet<void>(
      context: _deps.context(),
      // Same standard sheet chrome as the per-episode ⋮ menu.
      backgroundColor: AppThemeScope.of(_deps.context()).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => MergedQuickActionsMenu(
        title: _item.name,
        options: options,
        isTelevision: _deps.isTelevision(),
        onSelected: (action) async {
          Navigator.of(sheetCtx).pop();
          await _deps.onTraktAction()?.call(action);
          if (mounted && action == TraktItemMenuAction.clearWatchProgress) {
            _refreshAfterPlayback();
          }
          // Binding a source changes the pill's count, and "Remove from
          // Continue Watching" changes the resume label.
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// The Trakt sheet: watchlist / collection / watched as switches, plus an
  /// inline rating strip and the list actions.
  ///
  /// Unlike the app sheet this one stays open — a tracker sheet is somewhere
  /// you set several things at once, and each row re-reads the live status so
  /// the switches show the truth rather than an optimistic guess.
  void showQuickActionsMenu() {
    if (traktOnlyMenuOptions.isEmpty || _deps.onTraktAction() == null) return;
    showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: AppThemeScope.of(_deps.context()).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => MergedTraktSheet(
        title: _item.name,
        isTelevision: _deps.isTelevision(),
        status: _k.traktStatus,
        optionsFor: (status) => [
          for (final o
              in _deps.traktMenuBuilder()?.call(status) ??
                  _deps.traktMenuOptions())
            if (!appOwnedActions.contains(o.action)) o,
        ],
        onAction: (action) async {
          await _deps.onTraktAction()?.call(action);
          if (mounted && action == TraktItemMenuAction.clearTraktProgress)
            _refreshAfterPlayback();
        },
        onRate: _deps.onTraktRate(),
        statusLoader: _deps.traktStatusLoader(),
        // Keep the pill in sync with whatever the sheet did while it was open.
        onChanged: (status) {
          if (mounted) {
            setState(() {
              _k.traktStatus = status;
              _k.traktStatusResolved = true;
            });
          }
        },
      ),
    );
  }

  /// Simkl's own sheet — mirrors [_showQuickActionsMenu], but Simkl's five
  /// statuses are mutually exclusive, so they render as an exclusive toggle
  /// group instead of a list of "Move to X" commands.
  void showSimklQuickActionsMenu() {
    if (menuOptionsSimkl.isEmpty || _deps.onSimklAction() == null) return;
    showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: AppThemeScope.of(_deps.context()).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => MergedSimklSheet(
        title: _item.name,
        isTelevision: _deps.isTelevision(),
        status: _k.simklStatus,
        optionsFor: (status) =>
            _deps.simklMenuBuilder()?.call(status) ?? _deps.simklMenuOptions(),
        onAction: (action) async {
          await _deps.onSimklAction()?.call(action);
          if (mounted && action == SimklItemMenuAction.clearWatchProgress)
            _refreshAfterPlayback();
        },
        onRate: _deps.onSimklRate(),
        statusLoader: _deps.simklStatusLoader(),
        onChanged: (status) {
          if (mounted) {
            setState(() {
              _k.simklStatus = status;
              _k.simklStatusResolved = true;
            });
          }
        },
      ),
    );
  }

  void showMdblistQuickActionsMenu() {
    if (menuOptionsMdblist.isEmpty || _deps.onMdblistAction() == null) return;
    showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: AppThemeScope.of(_deps.context()).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Text(
                _item.name,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'MDBList',
                style: TextStyle(
                  color: kMdblistPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in menuOptionsMdblist)
                ListTile(
                  leading: Icon(option.icon, color: option.color),
                  title: Text(option.label),
                  onTap: () async {
                    await _deps.onMdblistAction()?.call(option.action);
                    if (mounted &&
                        option.action ==
                            MdblistItemMenuAction.clearWatchProgress)
                      _refreshAfterPlayback();
                    await _ta.loadMdblistStatus();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
