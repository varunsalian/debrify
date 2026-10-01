import 'package:flutter/widgets.dart';

import '../../features/discover/presentation/discover_bindings.dart';
import '../../features/discover/presentation/discover_loading.dart';
import '../../features/discover/presentation/discover_section.dart';
import '../../features/home/presentation/home_board_section.dart';
import '../../models/metadata_preferences.dart';
import 'home_catalog_presentation_composition.dart';
import 'home_continuation_content_composition.dart';

typedef DiscoverCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() discoverMode,
  bool Function() isTelevision,
  DiscoverBindings Function() bindings,
  HomeCatalogPresentation Function() catalog,
  HomeContinuationContent Function() continuation,
  HomeBoardSection Function() board,
  Widget Function(DiscoverSection) buildPanel,
  bool mdblistEnabled,
});

typedef DiscoverComposition = ({
  DiscoverSection section,
  DiscoverLoading loading,
});

/// Constructs source presentation and loading; route bindings remain deferred.
DiscoverComposition createDiscover(DiscoverCompositionDeps deps) {
  late final DiscoverSection section;
  late final DiscoverLoading loading;
  section = DiscoverSection((
    bindings: deps.bindings,
    mounted: deps.mounted,
    discoverMode: deps.discoverMode,
    isTelevision: deps.isTelevision,
    discoveryEnabled: () =>
        deps.catalog().metadata.metadataFeaturePolicy?.features.contains(
          MetadataFeature.discovery,
        ) ==
        true,
    context: deps.context,
    setState: deps.setState,
    buildPanel: () => deps.buildPanel(section),
  ));
  loading = DiscoverLoading((
    source: () => deps.bindings().source,
    mounted: deps.mounted,
    mdblistEnabled: deps.mdblistEnabled,
    setState: deps.setState,
    metadataFeaturePolicy: () => deps.catalog().metadata.metadataFeaturePolicy,
    refreshMetadataFeaturePolicy: () =>
        deps.catalog().metadata.refreshMetadataFeaturePolicy(),
    loadContinueWatching: () =>
        deps.continuation().loading.loadContinueWatching(),
    loadTraktContinueWatching: ({refreshBound = true}) => deps
        .continuation()
        .loading
        .loadTraktContinueWatching(refreshBound: refreshBound),
    loadSimklContinueWatching: ({refreshBound = true}) => deps
        .continuation()
        .loading
        .loadSimklContinueWatching(refreshBound: refreshBound),
    loadMdblistContinueWatching: ({refreshBound = true}) => deps
        .continuation()
        .loading
        .loadMdblistContinueWatching(refreshBound: refreshBound),
    refreshBoundSources: () => deps.catalog().badges.refreshBoundSources(),
  ), () => deps.board().addonsById);
  return (section: section, loading: loading);
}
