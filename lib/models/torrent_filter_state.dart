import 'dart:collection';

import 'package:flutter/foundation.dart';

enum QualityTier { ultraHd, fullHd, hd, sd }

enum RipSourceCategory { web, bluRay, hdrip, dvdrip, cam, other }

@immutable
class TorrentFilterState {
  final Set<QualityTier> qualities;
  final Set<RipSourceCategory> ripSources;

  TorrentFilterState({
    Set<QualityTier> qualities = const <QualityTier>{},
    Set<RipSourceCategory> ripSources = const <RipSourceCategory>{},
  })  : qualities = _freeze(qualities),
        ripSources = _freeze(ripSources);

  const TorrentFilterState.empty()
      : qualities = const <QualityTier>{},
        ripSources = const <RipSourceCategory>{};

  bool get isEmpty => qualities.isEmpty && ripSources.isEmpty;

  TorrentFilterState copyWith({
    Set<QualityTier>? qualities,
    Set<RipSourceCategory>? ripSources,
  }) {
    return TorrentFilterState(
      qualities: qualities ?? this.qualities,
      ripSources: ripSources ?? this.ripSources,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TorrentFilterState &&
        setEquals(other.qualities, qualities) &&
        setEquals(other.ripSources, ripSources);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(qualities.toList()..sort((a, b) => a.index - b.index)),
    Object.hashAll(ripSources.toList()..sort((a, b) => a.index - b.index)),
  );
}

Set<T> _freeze<T>(Set<T> values) {
  if (values is UnmodifiableSetView<T>) {
    return values;
  }
  return Set.unmodifiable(values);
}
