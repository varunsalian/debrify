// Contract between the sports board controller and the guide data source.
//
// The controller (application layer) depends only on these abstractions;
// the SQLite implementation lives in `data/`.
import 'package:flutter/foundation.dart';

import 'sports_models.dart';

/// What a guide title or channel name must mention to be about one event:
/// every side, each by any of its normalized variants (a team game has two
/// sides; a tournament has one, its title).
@immutable
class SportsEventNeedles {
  const SportsEventNeedles(this.sides, {this.around, this.sport});

  final List<List<String>> sides;

  /// When the event is on (its start, or now while a multi-day event is
  /// live): a stream name dated days away from this is another game.
  final DateTime? around;

  /// The event's sport: a stream name labelled with another sport
  /// ("Volleyball: Temple vs East Carolina") is not this game.
  final SportKind? sport;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsEventNeedles &&
          other.around == around &&
          other.sport == sport &&
          other.sides.length == sides.length &&
          [
            for (var i = 0; i < sides.length; i++)
              listEquals(other.sides[i], sides[i]),
          ].every((same) => same));

  @override
  int get hashCode => Object.hash(
    around,
    sport,
    Object.hashAll([for (final s in sides) Object.hashAll(s)]),
  );
}

/// A read request against the user's IPTV guide.
@immutable
class SportsGuideQuery {
  const SportsGuideQuery({
    required this.fromUtc,
    required this.toUtc,
    required this.nowUtc,
    this.titleNeedles = const [],
    this.channelNeedles = const [],
    this.events = const [],
  });

  final DateTime fromUtc;
  final DateTime toUtc;
  final DateTime nowUtc;

  /// Normalized (see `normalizeSportsText`) title needles.
  final List<String> titleNeedles;

  /// Normalized channel base names.
  final List<String> channelNeedles;

  /// Per event: what a guide title must name in full to be kept (so common
  /// team words cannot fill the listing cap with news and other games), and
  /// what a channel's own name must name to be that event's channel.
  final List<SportsEventNeedles> events;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsGuideQuery &&
          other.fromUtc == fromUtc &&
          other.toUtc == toUtc &&
          other.nowUtc == nowUtc &&
          listEquals(other.titleNeedles, titleNeedles) &&
          listEquals(other.channelNeedles, channelNeedles) &&
          listEquals(other.events, events));

  @override
  int get hashCode => Object.hash(
    fromUtc,
    toUtc,
    nowUtc,
    Object.hashAll(titleNeedles),
    Object.hashAll(channelNeedles),
    Object.hashAll(events),
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
    this.namedChannels = const [],
  });

  static const empty = SportsGuideSnapshot();

  /// Titles matching a needle, in window.
  final List<SportsGuideListing> listings;

  /// Channels matching a channelNeedle.
  final List<SportsChannelRef> channels;

  /// Airing now on sports-group channels.
  final List<SportsGuideListing> liveSportsListings;

  /// Channels whose own name names an event ("Cricket 03: Bangladesh vs
  /// West Indies"), the way providers label their event streams.
  final List<SportsChannelRef> namedChannels;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsGuideSnapshot &&
          listEquals(other.listings, listings) &&
          listEquals(other.channels, channels) &&
          listEquals(other.liveSportsListings, liveSportsListings) &&
          listEquals(other.namedChannels, namedChannels));

  @override
  int get hashCode => Object.hash(
    Object.hashAll(listings),
    Object.hashAll(channels),
    Object.hashAll(liveSportsListings),
    Object.hashAll(namedChannels),
  );

  @override
  String toString() =>
      'SportsGuideSnapshot(listings: ${listings.length}, '
      'channels: ${channels.length}, live: ${liveSportsListings.length}, '
      'named: ${namedChannels.length})';
}

/// Supplies guide data for the sports board.
abstract interface class SportsGuideSource {
  Future<SportsGuideSnapshot> load(SportsGuideQuery query);
}
