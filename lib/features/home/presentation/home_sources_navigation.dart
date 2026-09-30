import 'package:flutter/material.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/custom_series_identity.dart';
import '../../../models/playback_meta.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/tv_keys.dart';

typedef HomeSourcesBuilder =
    Widget Function({
      required AdvancedSearchSelection selection,
      required PlaybackMeta meta,
      required bool isTelevision,
      bool bindMode,
      String? keywordSeed,
      bool forcePlayOnTap,
    });

/// Home's three Sources entry points share route ownership, not data policy.
/// The Sources feature continues to own searching, binding and playback.
class HomeSourcesNavigation {
  /// The Sources screen is supplied by the composition that binds Home to the
  /// Sources feature (see `homeSourcesNavigationProvider`).
  const HomeSourcesNavigation({required HomeSourcesBuilder buildScreen})
    : _buildScreen = buildScreen;

  final HomeSourcesBuilder _buildScreen;

  /// Detail/source-editor binding searches the whole title, never an episode.
  /// Both torrent and editable keyword entry points retain the same identity.
  Future<void> bindCatalog(
    BuildContext context, {
    required StremioMeta item,
    required String? progressId,
    required bool keyword,
    required PlaybackMeta Function(AdvancedSearchSelection) buildMeta,
    required bool Function() isTelevision,
    required bool Function() isCurrent,
    required Future<void> Function() onReturned,
  }) {
    if (!context.mounted || !isCurrent()) return Future.value();
    if (progressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No IMDb match to pin a source for "${item.name}".'),
          duration: const Duration(seconds: 3),
        ),
      );
      return Future.value();
    }
    final isSeries = item.type == 'series';
    final selection = AdvancedSearchSelection(
      imdbId: progressId,
      isSeries: isSeries,
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
      stremioAddonId: item.sourceAddon?.id,
      stremioAddonKey: CustomSeriesIdentity.isCustom(progressId)
          ? item.sourceAddon?.sourceBindingKey
          : null,
      stremioCatalogId: CustomSeriesIdentity.parse(progressId)?.catalogId,
    );
    final seed = !keyword
        ? null
        : isSeries
        ? '${item.name} complete'
        : (item.year != null && item.year!.isNotEmpty
              ? '${item.name} ${item.year}'
              : item.name);
    return bind(
      context,
      selection: selection,
      buildMeta: () => buildMeta(selection),
      isTelevision: isTelevision,
      keywordSeed: seed,
      isCurrent: isCurrent,
      onReturned: onReturned,
    );
  }

  Future<void> browse(
    BuildContext context, {
    required AdvancedSearchSelection selection,
    required PlaybackMeta Function() buildMeta,
    required bool Function() isTelevision,
    required bool forcePlayOnTap,
    required bool Function() isCurrent,
    required Future<void> Function() onReturned,
  }) async {
    if (!context.mounted || !isCurrent()) return;
    // All browse entry points retain the exact episode chosen by their caller.
    debugPrint(
      '[SeriesResume] picker-open title="${selection.title}" id=${selection.imdbId} '
      'target=S${selection.season}E${selection.episode} '
      'label="${selection.formattedLabel}"',
    );
    if (selection.imdbId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No IMDb match to find sources for "${selection.title}".',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    // Browsing historically captured metadata before pushing the route.
    final meta = buildMeta();
    await _push(
      context,
      isCurrent: isCurrent,
      onReturned: onReturned,
      build: () => TvHeldKeyGuard(
        child: _buildScreen(
          selection: selection,
          meta: meta,
          isTelevision: isTelevision(),
          forcePlayOnTap: forcePlayOnTap,
        ),
      ),
    );
  }

  Future<void> bind(
    BuildContext context, {
    required AdvancedSearchSelection selection,
    required PlaybackMeta Function() buildMeta,
    required bool Function() isTelevision,
    String? keywordSeed,
    required bool Function() isCurrent,
    required Future<void> Function() onReturned,
  }) => _push(
    context,
    isCurrent: isCurrent,
    onReturned: onReturned,
    // Binding historically read metadata in the route builder. Keep it lazy,
    // including subsequent route rebuilds, and do not add the browse key guard.
    build: () => _buildScreen(
      selection: selection,
      meta: buildMeta(),
      isTelevision: isTelevision(),
      bindMode: true,
      keywordSeed: keywordSeed,
    ),
  );

  Future<void> _push(
    BuildContext context, {
    required Widget Function() build,
    required bool Function() isCurrent,
    required Future<void> Function() onReturned,
  }) async {
    if (!context.mounted || !isCurrent()) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            context.mounted && isCurrent() ? build() : const SizedBox.shrink(),
      ),
    );
    if (!context.mounted || !isCurrent()) return;
    // Browse refreshes playback/CW as well as badges; binding refreshes badges.
    await onReturned();
  }
}
