import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/playback_meta.dart';
import '../../../models/series_source.dart';
import '../../../models/torrent.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/dialog_tap_guard.dart';
import '../application/saved_sources_controller.dart';
import '../application/source_binding_controller.dart';
import '../application/source_link_dependencies.dart';
import '../application/source_row_action_dependencies.dart';
import '../data/source_link_copier.dart';
import '../models/sources_session.dart';
import 'source_binding_bridge.dart';
import 'source_playback_bridge.dart';
import 'source_row_actions_sheet.dart';

typedef SourceActionDetails = ({
  AdvancedSearchSelection selection,
  PlaybackMeta meta,
  bool bindMode,
  bool forcePlayOnTap,
});

/// View-owned action presentation. Borrows context/dependencies and live guards;
/// application controllers retain mutations, while bridges retain legacy IO.
/// No search state, focus resources or asynchronous work starts on construction.
class SourceActions {
  SourceActions({
    required this.ref,
    required this.context,
    required this.session,
    required this.isMounted,
    required this.isActive,
    required this.details,
    required this.readVisible,
    required this.freezeStreaming,
    required this.bindingFor,
    required this.reloadBound,
  });

  final WidgetRef ref;
  final BuildContext context;
  final SourcesSession session;
  final bool Function() isMounted;
  final bool Function() isActive;
  final SourceActionDetails Function() details;
  final List<Torrent> Function() readVisible;
  final VoidCallback freezeStreaming;
  final SeriesSource? Function(Torrent) bindingFor;
  final Future<void> Function() reloadBound;

  String get _imdbId => details().selection.imdbId;
  bool get _isMovie => !details().selection.isSeries;

  void play(Torrent t, int i) {
    // Swallow a SELECT that leaks through as the row menu / provider picker
    // closes on TV (armed via DialogTapGuard.markKeyAction in the menu).
    if (DialogTapGuard.shouldIgnoreTap()) return;
    _playNow(t, i);
  }

  void _playNow(Torrent t, int i) {
    if (!isActive()) return;
    freezeStreaming();
    unawaited(
      ref
          .read(sourcePlaybackBridgeProvider)
          .play(
            context,
            t,
            forcePlay: details().forcePlayOnTap,
            meta: details().meta,
            // Use the rendered list so the index and in-player Sources switcher
            // stay in sync with the filter/sort order the user sees.
            sources: readVisible(),
            sourceIndex: i,
            searchKeyword: details().selection.title,
          )
          .then((_) => reloadBound()),
    );
  }

  void _snack(String message) {
    if (!isMounted()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  bool canCopy(Torrent torrent) =>
      ref.read(sourceLinkCopierProvider).canCopy(torrent);

  Future<void> copyLink(Torrent torrent) async {
    bool active() => isActive();
    if (!active()) return;
    final result = await ref
        .read(sourceLinkCopierProvider)
        .copy(
          torrent,
          canContinue: active,
          onResolving: () => _snack('Finding this IPTV episode…'),
        );
    if (!active()) return;
    final message = switch (result) {
      SourceLinkCopyResult.copied => 'Link copied to clipboard',
      SourceLinkCopyResult.chooseEpisode =>
        'Choose an episode before copying its IPTV link.',
      SourceLinkCopyResult.missingEpisode =>
        '${torrent.episodeIdentifier ?? 'This episode'} is not available in this IPTV series.',
      SourceLinkCopyResult.unavailableEpisode =>
        'Could not check this IPTV series. Try again.',
      SourceLinkCopyResult.noLink => 'No link available for this source.',
      SourceLinkCopyResult.retired => null,
    };
    if (message != null) _snack(message);
  }

  Future<void> pin(Torrent t) async {
    if (!isActive()) return;
    if (t.isExternalStream) {
      _snack("External links can't be pinned as a playback source.");
      return;
    }
    await _bindSource(
      (saveBinding, canContinue) => ref
          .read(sourceBindingBridgeProvider)
          .pin(
            context,
            t,
            imdbId: _imdbId,
            isMovie: _isMovie,
            saveBinding: saveBinding,
            canContinue: canContinue,
            addonCatalogId: details().selection.stremioCatalogId,
            addonCatalogKey: details().selection.stremioAddonKey,
          ),
    );
  }

  Future<void> _unpin(SeriesSource source) async {
    if (!isActive()) return;
    await ref.read(savedSourcesProvider(session).notifier).remove(source);
  }

  Future<void> pinLocal() => _bindSource(
    (saveBinding, canContinue) => ref
        .read(sourceBindingBridgeProvider)
        .pinLocal(
          context,
          imdbId: _imdbId,
          isMovie: _isMovie,
          saveBinding: saveBinding,
          canContinue: canContinue,
          title: details().selection.title,
          year: details().selection.year,
        ),
  );

  Future<void> _bindSource(SourceBindingOperation operation) async {
    if (!isActive()) return;
    final pickerRoute = ModalRoute.of(context);
    final navigator = pickerRoute?.navigator;
    final ready = await ref
        .read(sourceBindingProvider(session).notifier)
        .bind(operation, viewIsActive: () => isMounted());
    if (ready &&
        details().bindMode &&
        isActive() &&
        pickerRoute != null &&
        navigator != null &&
        navigator.mounted) {
      if (pickerRoute.isCurrent) {
        navigator.pop();
      } else if (pickerRoute.isActive) {
        // A delayed save closes this picker, never a newer route above it.
        navigator.removeRoute(pickerRoute);
      }
    }
  }

  void showMenu(Torrent t, int i) {
    if (!isActive()) return;
    freezeStreaming();
    final app = AppThemeScope.of(context);
    final binding = bindingFor(t);
    final playback = ref.read(sourcePlaybackBridgeProvider);
    final copier = ref.read(sourceLinkCopierProvider);
    final policy = ref.read(sourceRowActionPolicyProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.home.sheetBg,
      builder: (_) {
        final actions = policy.project(
          t,
          canCopy: copier.canCopy,
          supportsDownload: playback.supportsDownload,
        );
        return SourceRowActionsSheet(
          app: app,
          kind: actions.kind,
          bound: binding != null,
          onPlay: () => _playNow(t, i),
          onTogglePin: actions.canPin
              ? () => unawaited(binding != null ? _unpin(binding) : pin(t))
              : null,
          onCopy: actions.canCopy ? () => unawaited(copyLink(t)) : null,
          onDownload: actions.canDownload
              ? () {
                  if (!isActive()) return;
                  unawaited(playback.download(context, t));
                }
              : null,
        );
      },
    );
  }
}
