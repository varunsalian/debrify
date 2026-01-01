import 'dart:collection';

import 'package:flutter/foundation.dart';

enum QualityTier { ultraHd, fullHd, hd, sd }

enum RipSourceCategory { web, bluRay, hdrip, dvdrip, cam, other }

enum AudioLanguage {
  english,
  hindi,
  spanish,
  french,
  german,
  russian,
  chinese,
  japanese,
  korean,
  italian,
  portuguese,
  arabic,
  multiAudio,
}

@immutable
class TorrentFilterState {
  final Set<QualityTier> qualities;
  final Set<RipSourceCategory> ripSources;
  final Set<AudioLanguage> languages;

  TorrentFilterState({
    Set<QualityTier> qualities = const <QualityTier>{},
    Set<RipSourceCategory> ripSources = const <RipSourceCategory>{},
    Set<AudioLanguage> languages = const <AudioLanguage>{},
  })  : qualities = _freeze(qualities),
        ripSources = _freeze(ripSources),
        languages = _freeze(languages);

  const TorrentFilterState.empty()
      : qualities = const <QualityTier>{},
        ripSources = const <RipSourceCategory>{},
        languages = const <AudioLanguage>{};

  bool get isEmpty => qualities.isEmpty && ripSources.isEmpty && languages.isEmpty;

  TorrentFilterState copyWith({
    Set<QualityTier>? qualities,
    Set<RipSourceCategory>? ripSources,
    Set<AudioLanguage>? languages,
  }) {
    return TorrentFilterState(
      qualities: qualities ?? this.qualities,
      ripSources: ripSources ?? this.ripSources,
      languages: languages ?? this.languages,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TorrentFilterState &&
        setEquals(other.qualities, qualities) &&
        setEquals(other.ripSources, ripSources) &&
        setEquals(other.languages, languages);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(qualities.toList()..sort((a, b) => a.index - b.index)),
    Object.hashAll(ripSources.toList()..sort((a, b) => a.index - b.index)),
    Object.hashAll(languages.toList()..sort((a, b) => a.index - b.index)),
  );
}

Set<T> _freeze<T>(Set<T> values) {
  if (values is UnmodifiableSetView<T>) {
    return values;
  }
  return Set.unmodifiable(values);
}
