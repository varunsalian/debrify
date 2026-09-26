import 'package:flutter/material.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/play_loader_art.dart';
import '../../../widgets/cinema_sources_layout.dart';

/// Responsive Sources chrome. Search state, actions and focus remain with its view.
/// Lazy capability/provider inputs retain layout-time evaluation.
Widget buildSourceScreenFrame(
  BuildContext context, {
  required AdvancedSearchSelection selection,
  required String? keywordQuery,
  required bool bindMode,
  required bool isTelevision,
  required PlayLoaderArt? art,
  required String? posterUrl,
  required GlobalKey<CinemaSourcesLayoutState> cinemaKey,
  required ValueGetter<bool> canPinLocal,
  required VoidCallback onPinLocal,
  required ValueGetter<List<CinemaSourceProvider>> providers,
  required String? selectedProvider,
  required ValueChanged<String?> onProviderSelected,
  required VoidCallback onFocusResults,
  required ValueGetter<bool> isSourceFocused,
  required int resultCount,
  required bool searching,
  required bool failed,
  required Widget Function(ColorScheme scheme, bool cinema) bodyBuilder,
}) {
  final keywordMode = keywordQuery != null;
  final scheme = Theme.of(context).colorScheme;
  return LayoutBuilder(
    builder: (context, constraints) {
      final cinema = useCinemaSourcesLayout(
        constraints,
        isTelevision: isTelevision,
      );
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: cinema
            ? null
            : AppBar(
                title: Text(
                  keywordMode
                      ? 'Find a source for ${selection.title}'
                      : bindMode
                      ? 'Pick a source for ${selection.title}'
                      : selection.formattedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  // Pin an on-device file/folder as the source. Desktop only — hidden on
                  // Android/iOS (incl. Android TV) where local binding is unavailable, so
                  // it's never a dead-end D-pad stop.
                  if (canPinLocal())
                    IconButton(
                      tooltip: 'Pin an on-device file or folder',
                      icon: const Icon(Icons.folder_open_rounded),
                      onPressed: onPinLocal,
                    ),
                ],
              ),
        body: cinema
            ? SafeArea(
                child: CinemaSourcesLayout(
                  key: cinemaKey,
                  contextTitle: keywordMode ? keywordQuery : selection.title,
                  contextLabel: !keywordMode && selection.isSeries
                      ? selection.formattedLabel
                      : null,
                  art: keywordMode
                      ? null
                      : art ??
                            PlayLoaderArt(
                              posterUrl: posterUrl,
                              yearLabel: selection.year,
                            ),
                  title: keywordMode
                      ? 'Search results'
                      : bindMode
                      ? 'Pick a source'
                      : 'Choose a source',
                  subtitle: keywordMode
                      ? 'Find a source for ${selection.title}'
                      : selection.formattedLabel,
                  onBack: () => Navigator.of(context).maybePop(),
                  backLabel: keywordMode ? 'Back' : 'Details',
                  headerAction: canPinLocal()
                      ? IconButton(
                          tooltip: 'Pin an on-device file or folder',
                          icon: const Icon(Icons.folder_open_rounded),
                          onPressed: onPinLocal,
                        )
                      : null,
                  providers: providers(),
                  selectedProvider: selectedProvider,
                  onProviderSelected: onProviderSelected,
                  onFocusResults: onFocusResults,
                  isSourceFocused: isSourceFocused,
                  resultCount: resultCount,
                  searching: searching,
                  failed: failed,
                  isTelevision: isTelevision,
                  child: bodyBuilder(scheme, true),
                ),
              )
            : bodyBuilder(scheme, false),
      );
    },
  );
}
