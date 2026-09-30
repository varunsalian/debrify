import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/metadata_preferences.dart';
import '../application/discover_source_controller.dart';

typedef DiscoverLoadingDeps = ({
  DiscoverSourceController Function() source,
  bool Function() mounted,
  bool mdblistEnabled,
  void Function(VoidCallback) setState,
  MetadataPreferences? Function() metadataFeaturePolicy,
  Future<void> Function() refreshMetadataFeaturePolicy,
  Future<void> Function() loadContinueWatching,
  Future<void> Function({bool refreshBound}) loadTraktContinueWatching,
  Future<void> Function({bool refreshBound}) loadSimklContinueWatching,
  Future<void> Function({bool refreshBound}) loadMdblistContinueWatching,
  Future<void> Function() refreshBoundSources,
});

/// Primes Discover's continuation data and source inventory in their original order.
class DiscoverLoading {
  DiscoverLoading(this._deps, this._addonsById);
  final DiscoverLoadingDeps _deps;
  final Map<String, StremioAddon> _addonsById;

  /// Load Continue Watching + Trakt rows, then refresh the pinned-source badge
  /// counts once. The board's `_load` does this via `_refreshBoundSources`; the
  /// Trakt loader only refreshes bound counts when Trakt is connected, so
  /// non-Trakt users would otherwise never get badges in Discover.
  Future<void> primeRows() async {
    await Future.wait([
      _deps.loadContinueWatching(),
      _deps.loadTraktContinueWatching(refreshBound: false),
      // Populates _simklAll/_simklProgress for the Simkl source's Continue
      // Watching list (folded into that source, like Trakt's).
      _deps.loadSimklContinueWatching(refreshBound: false),
      _deps.loadMdblistContinueWatching(refreshBound: false),
    ]);
    if (_deps.mounted()) await _deps.refreshBoundSources();
  }

  /// Apply fixed/remembered sources from local preferences immediately, then
  /// hydrate add-ons separately. Add-on defaults wait only for the inventory
  /// needed to validate them, and a source picked during that wait always wins.
  Future<void> loadAddons() => _deps.source().load(
    isCurrent: _deps.mounted,
    mdblistEnabled: _deps.mdblistEnabled,
    discoveryEnabled: () async {
      if (_deps.metadataFeaturePolicy() == null) {
        await _deps.refreshMetadataFeaturePolicy();
      }
      return _deps.metadataFeaturePolicy()?.features.contains(
            MetadataFeature.discovery,
          ) ==
          true;
    },
    onInventory: (addons) {
      for (final addon in addons) {
        _addonsById.putIfAbsent(addon.id, () => addon);
      }
    },
    onChanged: () => _deps.setState(() {}),
  );
}
