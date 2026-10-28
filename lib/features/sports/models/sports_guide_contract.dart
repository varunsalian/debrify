// Contract between the sports board controller and the guide data source.
//
// The controller (application layer) depends only on these abstractions;
// the SQLite implementation lives in `data/`.
import 'package:flutter/foundation.dart';

import 'sports_models.dart';

/// A read request against the user's IPTV guide.
@immutable
class SportsGuideQuery {
  const SportsGuideQuery({
    required this.fromUtc,
    required this.toUtc,
    required this.nowUtc,
    this.titleNeedles = const [],
    this.channelNeedles = const [],
  });

  final DateTime fromUtc;
  final DateTime toUtc;
  final DateTime nowUtc;

  /// Normalized (see `normalizeSportsText`) title needles.
  final List<String> titleNeedles;

  /// Normalized channel base names.
  final List<String> channelNeedles;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsGuideQuery &&
          other.fromUtc == fromUtc &&
          other.toUtc == toUtc &&
          other.nowUtc == nowUtc &&
          listEquals(other.titleNeedles, titleNeedles) &&
          listEquals(other.channelNeedles, channelNeedles));

  @override
  int get hashCode => Object.hash(
    fromUtc,
    toUtc,
    nowUtc,
    Object.hashAll(titleNeedles),
    Object.hashAll(channelNeedles),
  );

  @override
  String toString() =>
      'SportsGuideQuery($fromUtc..$toUtc, '
      'titles: ${titleNeedles.length}, channels: ${channelNeedles.length})';
}

/// Everything the guide source found for one [SportsGuideQuery].
@immutable
class SportsGuideSnapshot {
  const SportsGuideSnapshot({
    this.listings = const [],
    this.channels = const [],
    this.liveSportsListings = const [],
  });

  static const empty = SportsGuideSnapshot();

  /// Titles matching a needle, in window.
  final List<SportsGuideListing> listings;

  /// Channels matching a channelNeedle.
  final List<SportsChannelRef> channels;

  /// Airing now on sports-group channels.
  final List<SportsGuideListing> liveSportsListings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsGuideSnapshot &&
          listEquals(other.listings, listings) &&
          listEquals(other.channels, channels) &&
          listEquals(other.liveSportsListings, liveSportsListings));

  @override
  int get hashCode => Object.hash(
    Object.hashAll(listings),
    Object.hashAll(channels),
    Object.hashAll(liveSportsListings),
  );

  @override
  String toString() =>
      'SportsGuideSnapshot(listings: ${listings.length}, '
      'channels: ${channels.length}, live: ${liveSportsListings.length})';
}

/// Supplies guide data for the sports board.
abstract interface class SportsGuideSource {
  Future<SportsGuideSnapshot> load(SportsGuideQuery query);
}
