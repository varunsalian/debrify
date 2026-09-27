import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/playback_meta.dart';
import '../../../utils/tv_keys.dart';
import '../../sources/presentation/sources_screen.dart';

typedef HomeSourcesBuilder =
    Widget Function({
      required AdvancedSearchSelection selection,
      required PlaybackMeta meta,
      required bool isTelevision,
      bool bindMode,
      String? keywordSeed,
      bool forcePlayOnTap,
    });

final homeSourcesNavigationProvider = Provider<HomeSourcesNavigation>(
  (ref) => const HomeSourcesNavigation(),
);

/// Home's three Sources entry points share route ownership, not data policy.
/// The Sources feature continues to own searching, binding and playback.
class HomeSourcesNavigation {
  const HomeSourcesNavigation({
    HomeSourcesBuilder buildScreen = SourcesScreen.new,
  }) : _buildScreen = buildScreen;

  final HomeSourcesBuilder _buildScreen;

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
