import '../../../models/torrent.dart';
import '../../../widgets/cinema_sources_layout.dart';
import '../models/keyword_results_state.dart';
import 'keyword_source_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/search_loading_animation.dart';
import '../models/keyword_search_state.dart';
import '../application/keyword_provider_selection.dart';

/// Keyword page states. Builders keep inactive result/navigation surfaces lazy.
class KeywordSearchPage extends StatelessWidget {
  const KeywordSearchPage({
    super.key,
    required this.search,
    required this.isTelevision,
    required this.messageBuilder,
    required this.sourcesBuilder,
    required this.resultsBuilder,
  });
  final KeywordSearchState search;
  final bool isTelevision;
  final Widget Function(IconData, String, String) messageBuilder;
  final WidgetBuilder sourcesBuilder, resultsBuilder;

  @override
  Widget build(BuildContext context) {
    if (search.loading) {
      // Branded phased loader (parity with the old screen) instead of a bare
      // spinner. Keyword search is never series-aware, so isSeries stays false.
      return SearchLoadingAnimation(
        phase: SearchPhase.searching,
        isTelevision: isTelevision,
      );
    }
    if (search.error != null) {
      return messageBuilder(
        Icons.error_outline_rounded,
        'Search failed',
        search.error!,
      );
    }
    if (search.query.isEmpty) {
      // Surface Sources before searching so users can enable/disable the
      // trackers that get queried up front.
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: sourcesBuilder(context),
            ),
          ),
          Expanded(
            child: messageBuilder(
              Icons.bolt_rounded,
              'Keyword torrent search',
              'Type a title and press search to find torrents across your '
                  'enabled sources, then tap one to play. Use Sources to choose '
                  'which trackers are queried.',
            ),
          ),
        ],
      );
    }
    return resultsBuilder(context);
  }
}

/// Progress feedback while already displayed rows remain interactive.
class KeywordSearchingStrip extends StatelessWidget {
  const KeywordSearchingStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 8),
          Text(
            'Still searching sources…',
            style: TextStyle(
              fontSize: 11.5,
              color: app.fade(app.core.tx, 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parked arrivals: touch adopts; remote activation also returns focus to rows.
class KeywordNewResultsPill extends StatelessWidget {
  const KeywordNewResultsPill({
    super.key,
    required this.count,
    required this.focusNode,
    required this.onAdopt,
    required this.onFocusResults,
    required this.onFocusToolbar,
  });
  final int count;
  final FocusNode focusNode;
  final VoidCallback onAdopt, onFocusResults, onFocusToolbar;
  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final n = count;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(e.logicalKey)) {
          onAdopt();
          onFocusResults();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          onFocusResults();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          onFocusToolbar();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          return GestureDetector(
            onTap: onAdopt,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: focused ? app.core.tx : accent,
                borderRadius: app.shape.brPill,
                border: Border.all(
                  color: focused ? app.core.tx : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 14,
                    // Unfocused the pill is FILLED with the accent, so its ink
                    // has to be scored against it — white is invisible on the
                    // near-white accents (Noir, Frost, Vault). The focused
                    // branch keeps its dark ink on the white focus fill.
                    color: focused
                        ? const Color(0xFF17131F)
                        : app.inkOn(accent),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$n new result${n == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: focused
                          ? const Color(0xFF17131F)
                          : app.inkOn(accent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cinema provider rail or mobile selection overlay around the same result body.
class KeywordResultsFrame extends StatelessWidget {
  const KeywordResultsFrame({
    super.key,
    required this.cinema,
    required this.narrow,
    required this.isTelevision,
    required this.search,
    required this.results,
    required this.full,
    required this.sources,
    required this.cinemaKey,
    required this.onProviderSelected,
    required this.onFocusAbove,
    required this.onFocusResults,
    required this.isSourceFocused,
    required this.child,
    this.selectionOverlay,
  });
  final bool cinema, narrow, isTelevision;
  final KeywordSearchState search;
  final KeywordResultsState results;
  final List<Torrent> full;
  final List<String> sources;
  final Key cinemaKey;
  final ValueChanged<String?> onProviderSelected;
  final VoidCallback onFocusAbove, onFocusResults;
  final bool Function() isSourceFocused;
  final Widget child;
  final Widget? selectionOverlay;

  @override
  Widget build(BuildContext context) {
    if (cinema) {
      final counts = <String, int>{};
      for (final torrent in full) {
        final source = keywordSourceOf(torrent);
        counts[source] = (counts[source] ?? 0) + 1;
      }
      return CinemaSourcesLayout(
        key: cinemaKey,
        contextTitle: search.query,
        title: results.selectionMode ? 'Select sources' : 'Search results',
        subtitle: results.selectionMode
            ? '${results.selected.length} selected'
            : 'Torrents matching your keyword',
        providers: [
          CinemaSourceProvider(
            id: null,
            label: 'All sources',
            count: full.length,
          ),
          for (final source in sources)
            CinemaSourceProvider(
              id: source,
              label: keywordSourceLabel(full, source),
              count: counts[source] ?? 0,
            ),
        ],
        selectedProvider: results.sourceTab,
        providersEnabled: !results.selectionMode,
        onProviderSelected: onProviderSelected,
        onFocusAbove: onFocusAbove,
        onFocusResults: onFocusResults,
        isSourceFocused: isSourceFocused,
        resultCount: results.results.length,
        searching: search.searching,
        isTelevision: isTelevision,
        child: child,
      );
    }
    if (!narrow) return child;
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (selectionOverlay != null) selectionOverlay!,
      ],
    );
  }
}
