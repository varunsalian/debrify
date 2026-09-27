import 'home_bound_source_tile.dart';
import 'package:flutter/material.dart';

import '../../../models/series_source.dart';
import '../../../models/stremio_addon.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/clear_pinned_sources_button.dart';
import '../../../widgets/add_source_picker_dialog.dart';
import '../../../screens/debrid_downloads_screen.dart';
import '../../../screens/torbox/torbox_downloads_screen.dart';
import '../../../screens/premiumize/premiumize_files_screen.dart';
import '../../../screens/alldebrid/alldebrid_files_screen.dart';
import '../../../screens/pikpak/pikpak_files_screen.dart';
import '../../sources/presentation/local_source_picker.dart';
import '../data/home_source_editing_repository.dart';

/// One detail action's editor and add-source navigation. Persistence and native
/// picking are injected; accepted routes borrow the originating view guard.
class HomeSourceEditor {
  const HomeSourceEditor({
    required this.context,
    required this.item,
    required this.id,
    required this.repository,
    required this.localPicker,
    required this.isCurrent,
    required this.refreshBindings,
    required this.showMessage,
    required this.openTorrent,
    required this.openKeyword,
  });

  final BuildContext context;
  final StremioMeta item;
  final String? id;
  final HomeSourceEditingRepository repository;
  final LocalSourcePicker localPicker;
  final bool Function() isCurrent;
  final Future<void> Function() refreshBindings;
  final void Function(String) showMessage;
  final void Function(StremioMeta) openTorrent, openKeyword;
  bool current() => context.mounted && isCurrent();

  /// "Select/Edit Source" entry: edit dialog when a source is already bound,
  /// otherwise the add-source picker.
  Future<void> open() async {
    if (!current()) return;
    final imdb = id;
    final bound = imdb == null
        ? const <SeriesSource>[]
        : await repository.load(imdb, isCurrent: current);
    if (!current()) return;
    if (bound == null) return;
    if (bound.isNotEmpty) {
      await _showEditSourceDialog(bound);
    } else {
      await _showAddSourcePicker();
    }
  }

  /// Manage the bound sources for [item]: list them, reorder by priority
  /// (series — first match wins), delete individually, Remove All, or add
  /// another via the picker. Ported from the catalog/aggregated detail flow.
  Future<void> _showEditSourceDialog(List<SeriesSource> initial) async {
    final imdbId = id;
    if (imdbId == null) return;
    final isMovie = item.type == 'movie';
    final sources = List<SeriesSource>.of(initial);
    if (sources.isEmpty) return;

    // [closeIfEmpty] pops the dialog via its OWN route (passed in from the
    // builder) when the last source is removed — robust to nested navigators,
    // and a callback (not a BuildContext) so it's safe across the awaits here.
    Future<void> refreshInto(
      void Function(void Function()) setDialogState,
      VoidCallback closeIfEmpty,
      bool Function() dialogCurrent,
    ) async {
      final updated = await repository.load(imdbId, isCurrent: dialogCurrent);
      if (!dialogCurrent() || updated == null) return;
      setDialogState(() {
        sources
          ..clear()
          ..addAll(updated);
      });
      await refreshBindings();
      if (updated.isEmpty) closeIfEmpty();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final app = AppThemeScope.of(dialogContext);
            bool dialogCurrent() => dialogContext.mounted && current();
            void closeIfEmpty() {
              if (!dialogCurrent()) return;
              final route = ModalRoute.of(dialogContext);
              if (route == null) return;
              final navigator = Navigator.of(dialogContext);
              if (route.isCurrent) {
                navigator.pop();
              } else {
                navigator.removeRoute(route);
              }
            }

            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: app.shape.br(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  maxHeight: 500,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: isMovie
                            ? ListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                itemBuilder: (context, index) =>
                                    buildHomeBoundSourceTile(
                                      context,
                                      key: ValueKey(sources[index].bindingKey),
                                      source: sources[index],
                                      index: index,
                                      showDragHandle: false,
                                      onDelete: () async {
                                        if (!await repository.remove(
                                          imdbId,
                                          sources[index],
                                          isCurrent: dialogCurrent,
                                        )) {
                                          return;
                                        }
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                          dialogCurrent,
                                        );
                                      },
                                    ),
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                onReorder: (oldIndex, newIndex) async {
                                  if (!dialogCurrent()) return;
                                  if (newIndex > oldIndex) newIndex--;
                                  setDialogState(() {
                                    final moved = sources.removeAt(oldIndex);
                                    sources.insert(newIndex, moved);
                                  });
                                  if (await repository.replace(
                                    imdbId,
                                    List.of(sources),
                                    isCurrent: dialogCurrent,
                                  )) {
                                    await refreshBindings();
                                  }
                                },
                                proxyDecorator: (child, index, animation) =>
                                    Material(
                                      color: Colors.transparent,
                                      elevation: 4,
                                      child: child,
                                    ),
                                itemBuilder: (context, index) =>
                                    buildHomeBoundSourceTile(
                                      context,
                                      key: ValueKey(sources[index].bindingKey),
                                      source: sources[index],
                                      index: index,
                                      onDelete: () async {
                                        if (!await repository.remove(
                                          imdbId,
                                          sources[index],
                                          isCurrent: dialogCurrent,
                                        )) {
                                          return;
                                        }
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                          dialogCurrent,
                                        );
                                      },
                                    ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              autofocus: true,
                              onPressed: () {
                                if (!dialogCurrent()) return;
                                closeIfEmpty();
                                _showAddSourcePicker();
                              },
                              icon: Icon(
                                isMovie
                                    ? Icons.swap_horiz_rounded
                                    : Icons.add_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isMovie ? 'Change Source' : 'Add Source',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: app.shape.br(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClearPinnedSourcesButton(
                              onClear: () async {
                                if (!await repository.replace(
                                  imdbId,
                                  [],
                                  isCurrent: dialogCurrent,
                                )) {
                                  return;
                                }
                                await refreshBindings();
                                closeIfEmpty();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Add-source picker: Torrent Search (imdb) / Keyword Search (free-text) /
  /// Local file plus every configured cloud provider.
  Future<void> _showAddSourcePicker() async {
    if (!current()) return;
    final imdbId = id;
    if (imdbId == null) {
      showMessage('No IMDb match to pin a source for "${item.name}".');
      return;
    }
    // Capture the navigator before the awaits so the RD/TorBox push closures
    // don't reference `context` across an async gap.
    final navigator = Navigator.of(context);
    final available = await repository.providers(isCurrent: current);
    if (!context.mounted || !current() || available == null) return;
    final rdEnabled = available.rd;
    final torboxEnabled = available.torbox;
    final premiumizeEnabled = available.premiumize;
    final allDebridEnabled = available.allDebrid;
    final pikpakEnabled = available.pikpak;

    final isMovie = item.type == 'movie';
    final supportsLocal = localPicker.disabledReason == null;

    Future<void> saveSource(SeriesSource source) async {
      if (await repository.save(
        imdbId,
        source,
        isMovie: isMovie,
        isCurrent: current,
      )) {
        await refreshBindings();
      }
    }

    Future<void> push(WidgetBuilder builder) async {
      if (!current()) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (context) =>
              current() ? builder(context) : const SizedBox.shrink(),
        ),
      );
    }

    // No cloud providers and no local option → go straight to torrent search.
    if (!rdEnabled &&
        !torboxEnabled &&
        !premiumizeEnabled &&
        !allDebridEnabled &&
        !pikpakEnabled &&
        !supportsLocal) {
      openTorrent(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () {
        if (current()) openTorrent(item);
      },
      onKeywordSearch: () {
        if (current()) openKeyword(item);
      },
      onLocal: supportsLocal ? () => _pickAndSaveLocalSource() : null,
      localDisabledReason: localPicker.disabledReason,
      onRealDebrid: rdEnabled
          ? () => push(
              (_) => DebridDownloadsScreen(
                isPushedRoute: true,
                initialSearchQuery: item.name,
                selectSourceMode: true,
                onSourceSelected: saveSource,
              ),
            )
          : null,
      onTorbox: torboxEnabled
          ? () => push(
              (_) => TorboxDownloadsScreen(
                isPushedRoute: true,
                initialSearchQuery: item.name,
                selectSourceMode: true,
                onSourceSelected: saveSource,
              ),
            )
          : null,
      onPremiumize: premiumizeEnabled
          ? () => push(
              (_) => PremiumizeFilesScreen(
                isPushedRoute: true,
                initialSearchQuery: item.name,
                selectSourceMode: true,
                onSourceSelected: saveSource,
              ),
            )
          : null,
      onAllDebrid: allDebridEnabled
          ? () => push(
              (_) => AllDebridFilesScreen(
                isPushedRoute: true,
                initialSearchQuery: item.name,
                selectSourceMode: true,
                onSourceSelected: saveSource,
              ),
            )
          : null,
      onPikPak: pikpakEnabled
          ? () => push(
              (_) => PikPakFilesScreen(
                isPushedRoute: true,
                selectSourceMode: true,
                onSourceSelected: saveSource,
              ),
            )
          : null,
    );
  }

  Future<void> _pickAndSaveLocalSource() async {
    if (!current()) return;
    final imdbId = id;
    if (imdbId == null) return;
    final SeriesSource? source;
    if (item.type == 'series') {
      source = await localPicker.pickSeriesSource(
        context,
        title: item.name,
        canContinue: current,
      );
    } else {
      source = await localPicker.pickMovieSource(
        context,
        title: item.name,
        year: item.year,
        canContinue: current,
      );
    }
    if (source == null || !current()) return;
    if (!await repository.save(
      imdbId,
      source,
      isMovie: item.type != 'series',
      isCurrent: current,
    )) {
      return;
    }
    await refreshBindings();
    if (!current()) return;
    showMessage('Local source set: ${source.torrentName}');
  }
}
