import 'dart:async';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/widgets/detail/detail_primary_sources.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

class CatalogDetailBoundSources {
  final CatalogDetailDependencies _deps;

  CatalogDetailBoundSources(this._deps);

  CatalogDetailPrimaryAction get _p => _deps.parts.primaryAction;

  /// Re-read this title's bound-source count and flip the Play accent to match.
  Future<void> refreshBoundState() async {
    final imdb = boundKey();
    if (imdb == null) return;
    final bound = (await SeriesSourceService.getSources(imdb)).isNotEmpty;
    if (_deps.mounted() && bound != _deps.hasBoundSource) {
      _deps.setState(() => _deps.hasBoundSource = bound);
    }
  }

  /// The imdb key the binding store is keyed on — mirrors the host's `_imdbOf`
  /// (a `tt…` id, whether it rode in as `imdbId` or the raw catalog id).
  String? boundKey() {
    final item = _deps.item();
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  bool get canBrowsePrimarySources =>
      _deps.enablePrimarySourcesHold() &&
      (_deps.presentedItem().type != 'series' ||
          _deps.onBrowsePrimaryEpisodeSources() != null);

  void browsePrimarySources() {
    unawaited(browsePrimarySourcesAsync());
  }

  Future<void> browsePrimarySourcesAsync() async {
    if (_deps.presentedItem().type != 'series') {
      _deps.onBrowse()();
      return;
    }

    final openEpisode = _deps.onBrowsePrimaryEpisodeSources();
    if (openEpisode == null) return;

    final rules = await QuickPlayStorage.getQuickPlayRules(isMovie: false);
    if (!_deps.mounted()) return;

    final canBrowsePacks =
        _deps.onTraktAction() != null &&
        _deps.traktMenuOptions().any(
          (option) => option.action == TraktItemMenuAction.searchPacks,
        );
    if (!rules.preferSeriesPacks || !canBrowsePacks) {
      await openEpisode();
      return;
    }

    final choice = await showDetailPrimarySourcesSheet(
      _deps.context(),
      title: _deps.presentedItem().name,
      isTelevision: _deps.isTelevision(),
      episodeLabel: _p.resumeSeason == null || _p.resumeEpisode == null
          ? null
          : 'S${_p.resumeSeason}E${_p.resumeEpisode}',
    );
    if (!_deps.mounted() || choice == null) return;

    switch (choice) {
      case DetailPrimarySourceChoice.seasonPacks:
        _deps.onTraktAction()?.call(TraktItemMenuAction.searchPacks);
        return;
      case DetailPrimarySourceChoice.episode:
        await openEpisode();
        return;
    }
  }
}
