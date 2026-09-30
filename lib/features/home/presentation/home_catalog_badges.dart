import 'package:flutter/foundation.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_bound_counts_controller.dart';
import '../application/home_pikpak_only_controller.dart';
import 'home_board_bindings.dart';
import 'home_board_section.dart';
import 'home_continuation_section.dart';

typedef HomeCatalogBadgesDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  HomeBoardBindings Function() bindings,
});

/// Reads pinned-source badges and the provider capability used by catalog actions.
class HomeCatalogBadges {
  HomeCatalogBadges(this._deps, this._boardSection, this._continuationSection);
  final HomeCatalogBadgesDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeContinuationSection _continuationSection;

  /// True when PikPak is the ONLY configured provider. PikPak can't quick-play
  /// (it queues a cloud download), so catalog "Play" is hidden — matching Home.
  HomePikpakOnlyController get pikpakOnlyController => _deps.bindings().pikpak;
  bool get pikpakOnly => pikpakOnlyController.current;

  /// imdbId → number of pinned (bound) sources — drives the board tile badge,
  /// detail Sources tint, and the Episodes "Source(s)" button count.
  HomeBoundCountsController get boundCountsController =>
      _deps.bindings().boundCounts;
  Map<String, int> get boundCounts => boundCountsController.current;

  /// Stable progress key, including supported native provider identities.
  String? imdbOf(StremioMeta item) {
    final id = item.progressId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  bool isBound(StremioMeta item) {
    final id = imdbOf(item);
    return id != null && (boundCounts[id] ?? 0) > 0;
  }

  int boundCountFor(StremioMeta item) {
    final id = imdbOf(item);
    return id == null ? 0 : (boundCounts[id] ?? 0);
  }

  /// Re-read how many pinned sources each currently-displayed title has. Called
  /// after sections load and after any bind/unbind/playback.
  Future<void> refreshBoundSources() {
    // Cover every on-screen tile that renders a bound badge: catalog sections
    // AND the Continue Watching rows (whose titles may not appear in any
    // section, so editing their sources must still refresh the CW card badge).
    final items = [
      for (final section in _boardSection.sections) ...section.items,
      ..._continuationSection.cwMovies,
      ..._continuationSection.cwSeries,
      ..._continuationSection.traktMovies,
      ..._continuationSection.traktSeries,
      ..._continuationSection.simklMovies,
      ..._continuationSection.simklSeries,
      ..._continuationSection.mdblistMovies,
      ..._continuationSection.mdblistSeries,
    ];
    return boundCountsController.load(
      ids: items.map(imdbOf),
      isCurrent: () => _deps.mounted(),
      onAccepted: () => _deps.setState(() {}),
    );
  }

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> refreshPikpakOnly() => pikpakOnlyController.load(
    isCurrent: () => _deps.mounted(),
    onChanged: () => _deps.setState(() {}),
  );
}
