import 'dart:collection';

import 'package:flutter/foundation.dart';

enum QualityTier { ultraHd, fullHd, hd, sd }

/// A release's dynamic range, as read off its name.
///
/// Two values, not one per HDR flavour: the question this answers is "can my
/// display show this properly", and Dolby Vision, HDR10, HDR10+ and HLG all
/// answer it the same way. Picking [sdr] alone is the "exclude HDR" the
/// feature request asked for; picking both (or neither) filters nothing.
///
/// [sdr] is the ABSENCE of an HDR tag, so it is a guess in a way the other
/// facets aren't: a release that is HDR but doesn't say so reads as SDR. Same
/// name-based limitation the language facet already carries.
enum DynamicRange { sdr, hdr }

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

/// File-size buckets (binary GiB, matching the `_formatSize`/`_fmtSize`
/// display convention). Boundaries are half-open: a torrent falls in exactly
/// one bucket. Applied to movies + all keyword results only — NOT to series,
/// where addon packs report a single-episode size (see the Search tab
/// gating). Torrents with an unknown size (`sizeBytes == 0`) match no bucket
/// and are hidden while a size facet is active.
enum SizeBucket {
  under500mb,
  mb500to1gb,
  gb1to1p5,
  gb1p5to2p5,
  gb2p5to4,
  gb4to6,
  gb6to10,
  gb10to20,
  gb20to40,
  over40gb,
}

const int _mib = 1024 * 1024;
const int _gib = 1024 * _mib;

/// The single bucket a byte count belongs to, or null for unknown (<= 0).
/// Boundaries are half-open (`[low, high)`) so every positive size lands in
/// exactly one bucket.
SizeBucket? sizeBucketForBytes(int bytes) {
  if (bytes <= 0) return null;
  if (bytes < 500 * _mib) return SizeBucket.under500mb;
  if (bytes < _gib) return SizeBucket.mb500to1gb;
  if (bytes < (_gib * 3) ~/ 2) return SizeBucket.gb1to1p5;
  if (bytes < (_gib * 5) ~/ 2) return SizeBucket.gb1p5to2p5;
  if (bytes < 4 * _gib) return SizeBucket.gb2p5to4;
  if (bytes < 6 * _gib) return SizeBucket.gb4to6;
  if (bytes < 10 * _gib) return SizeBucket.gb6to10;
  if (bytes < 20 * _gib) return SizeBucket.gb10to20;
  if (bytes < 40 * _gib) return SizeBucket.gb20to40;
  return SizeBucket.over40gb;
}

@immutable
class TorrentFilterState {
  final Set<QualityTier> qualities;
  final Set<RipSourceCategory> ripSources;
  final Set<AudioLanguage> languages;
  final Set<SizeBucket> sizes;
  final Set<DynamicRange> dynamicRanges;

  TorrentFilterState({
    Set<QualityTier> qualities = const <QualityTier>{},
    Set<RipSourceCategory> ripSources = const <RipSourceCategory>{},
    Set<AudioLanguage> languages = const <AudioLanguage>{},
    Set<SizeBucket> sizes = const <SizeBucket>{},
    Set<DynamicRange> dynamicRanges = const <DynamicRange>{},
  })  : qualities = _freeze(qualities),
        ripSources = _freeze(ripSources),
        languages = _freeze(languages),
        sizes = _freeze(sizes),
        dynamicRanges = _freeze(dynamicRanges);

  const TorrentFilterState.empty()
      : qualities = const <QualityTier>{},
        ripSources = const <RipSourceCategory>{},
        languages = const <AudioLanguage>{},
        sizes = const <SizeBucket>{},
        dynamicRanges = const <DynamicRange>{};

  bool get isEmpty =>
      qualities.isEmpty &&
      ripSources.isEmpty &&
      languages.isEmpty &&
      sizes.isEmpty &&
      dynamicRanges.isEmpty;

  TorrentFilterState copyWith({
    Set<QualityTier>? qualities,
    Set<RipSourceCategory>? ripSources,
    Set<AudioLanguage>? languages,
    Set<SizeBucket>? sizes,
    Set<DynamicRange>? dynamicRanges,
  }) {
    return TorrentFilterState(
      qualities: qualities ?? this.qualities,
      ripSources: ripSources ?? this.ripSources,
      languages: languages ?? this.languages,
      sizes: sizes ?? this.sizes,
      dynamicRanges: dynamicRanges ?? this.dynamicRanges,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TorrentFilterState &&
        setEquals(other.qualities, qualities) &&
        setEquals(other.ripSources, ripSources) &&
        setEquals(other.languages, languages) &&
        setEquals(other.sizes, sizes) &&
        setEquals(other.dynamicRanges, dynamicRanges);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(qualities.toList()..sort((a, b) => a.index - b.index)),
    Object.hashAll(ripSources.toList()..sort((a, b) => a.index - b.index)),
    Object.hashAll(languages.toList()..sort((a, b) => a.index - b.index)),
    Object.hashAll(sizes.toList()..sort((a, b) => a.index - b.index)),
    Object.hashAll(
      dynamicRanges.toList()..sort((a, b) => a.index - b.index),
    ),
  );
}

Set<T> _freeze<T>(Set<T> values) {
  if (values is UnmodifiableSetView<T>) {
    return values;
  }
  return Set.unmodifiable(values);
}
