// Immutable domain models for the sports board.
//
// Pure Dart: only `package:flutter/foundation.dart` is allowed here (for
// `@immutable` and `listEquals`). No UI, data or application imports.
import 'package:flutter/foundation.dart';

/// Broad sport family used for grouping and iconography.
enum SportKind {
  soccer,
  basketball,
  americanFootball,
  hockey,
  baseball,
  motorsport,
}

/// Lifecycle of a fixture as shown on the board.
enum SportsEventStatus { scheduled, live, finished, postponed }

/// A league/competition the user can follow.
@immutable
class SportsLeague {
  const SportsLeague({
    required this.id,
    required this.name,
    required this.shortName,
    required this.sport,
    this.espnPath,
    this.importance = 0,
  });

  /// Stable identifier, e.g. `'ucl'`.
  final String id;

  /// Full display name, e.g. `'Champions League'`.
  final String name;

  /// Compact display name, e.g. `'UCL'`.
  final String shortName;

  final SportKind sport;

  /// ESPN scoreboard path segment, e.g. `'soccer/uefa.champions'`;
  /// null when the league is not backed by an ESPN feed.
  final String? espnPath;

  /// Higher values render more prominently.
  final int importance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SportsLeague && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SportsLeague($id)';
}

/// A team competing in an event.
@immutable
class SportsTeam {
  const SportsTeam({
    required this.id,
    required this.name,
    required this.shortName,
    required this.abbreviation,
    this.logoUrl,
    this.color,
  });

  final String id;
  final String name;
  final String shortName;
  final String abbreviation;
  final String? logoUrl;

  /// ARGB colour, e.g. `0xFFEF0107`.
  final int? color;

  /// Follow/cache key scoped to a league: `'<leagueId>:<teamId>'`.
  String keyIn(String leagueId) => '$leagueId:$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsTeam &&
          other.id == id &&
          other.name == name &&
          other.shortName == shortName &&
          other.abbreviation == abbreviation &&
          other.logoUrl == logoUrl &&
          other.color == color);

  @override
  int get hashCode =>
      Object.hash(id, name, shortName, abbreviation, logoUrl, color);

  @override
  String toString() => 'SportsTeam($id, $name)';
}

/// A single fixture (team game or non-team event such as an F1 race).
@immutable
class SportsEvent {
  const SportsEvent({
    required this.id,
    required this.leagueId,
    required this.start,
    required this.status,
    this.home,
    this.away,
    this.homeScore,
    this.awayScore,
    this.title,
    this.subtitle,
    this.clock,
    this.statusLabel = '',
    this.broadcasts = const [],
  });

  final String id;
  final String leagueId;

  /// Always UTC.
  final DateTime start;
  final SportsEventStatus status;
  final SportsTeam? home;
  final SportsTeam? away;
  final int? homeScore;
  final int? awayScore;

  /// Non-team events (F1 race); null for team games.
  final String? title;

  /// Venue or circuit.
  final String? subtitle;

  /// Live clock, e.g. `"41'"` or `"Q3 5:12"`.
  final String? clock;

  /// e.g. `'FT'`, `'Postponed'`, `''`.
  final String statusLabel;

  /// Broadcaster names, deduped, in feed order.
  final List<String> broadcasts;

  bool get isTeamEvent => home != null && away != null;

  String get displayTitle => title ?? '${home!.name} v ${away!.name}';

  /// teamKey is `'<leagueId>:<teamId>'`.
  bool involvesTeam(String teamKey) =>
      home?.keyIn(leagueId) == teamKey || away?.keyIn(leagueId) == teamKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsEvent &&
          other.id == id &&
          other.leagueId == leagueId &&
          other.start == start &&
          other.status == status &&
          other.home == home &&
          other.away == away &&
          other.homeScore == homeScore &&
          other.awayScore == awayScore &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.clock == clock &&
          other.statusLabel == statusLabel &&
          listEquals(other.broadcasts, broadcasts));

  @override
  int get hashCode => Object.hash(
    id,
    leagueId,
    start,
    status,
    home,
    away,
    homeScore,
    awayScore,
    title,
    subtitle,
    clock,
    statusLabel,
    Object.hashAll(broadcasts),
  );

  @override
  String toString() => 'SportsEvent($leagueId/$id, ${status.name})';
}

/// A user's IPTV channel that might show an event.
@immutable
class SportsChannelRef {
  const SportsChannelRef({
    required this.name,
    required this.url,
    this.logoUrl,
    this.group,
    this.playlistId,
    this.attributes = const {},
    this.httpHeaders = const {},
  });

  final String name;
  final String url;
  final String? logoUrl;
  final String? group;
  final String? playlistId;
  final Map<String, String> attributes;
  final Map<String, String> httpHeaders;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsChannelRef &&
          other.url == url &&
          other.playlistId == playlistId);

  @override
  int get hashCode => Object.hash(url, playlistId);

  @override
  String toString() => 'SportsChannelRef($name, $url)';
}

/// One EPG programme on one channel.
@immutable
class SportsGuideListing {
  const SportsGuideListing({
    required this.channel,
    required this.title,
    required this.start,
    required this.stop,
  });

  final SportsChannelRef channel;
  final String title;

  /// UTC.
  final DateTime start;

  /// UTC.
  final DateTime stop;

  bool airsAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsGuideListing &&
          other.channel == channel &&
          other.title == title &&
          other.start == start &&
          other.stop == stop);

  @override
  int get hashCode => Object.hash(channel, title, start, stop);

  @override
  String toString() => 'SportsGuideListing(${channel.name}, $title)';
}

/// How a [SportsWatchOption] was found.
enum SportsMatchKind { guide, broadcaster }

/// One watchable option for an event, either confirmed in the guide or
/// inferred from a broadcaster name.
@immutable
class SportsWatchOption {
  const SportsWatchOption({
    required this.channel,
    required this.kind,
    this.listing,
    this.variants = const [],
  });

  /// The best-quality copy.
  final SportsChannelRef channel;
  final SportsMatchKind kind;

  /// Set for `kind == guide`.
  final SportsGuideListing? listing;

  /// Other copies merged into this option.
  final List<SportsChannelRef> variants;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsWatchOption &&
          other.channel == channel &&
          other.kind == kind &&
          other.listing == listing &&
          listEquals(other.variants, variants));

  @override
  int get hashCode =>
      Object.hash(channel, kind, listing, Object.hashAll(variants));

  @override
  String toString() => 'SportsWatchOption(${channel.name}, ${kind.name})';
}

/// Guide-confirmed and possible watch options for one event.
@immutable
class SportsWatchOptions {
  const SportsWatchOptions({this.guide = const [], this.possible = const []});

  static const empty = SportsWatchOptions();

  final List<SportsWatchOption> guide;
  final List<SportsWatchOption> possible;

  bool get isEmpty => guide.isEmpty && possible.isEmpty;

  int get count => guide.length + possible.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsWatchOptions &&
          listEquals(other.guide, guide) &&
          listEquals(other.possible, possible));

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(guide), Object.hashAll(possible));

  @override
  String toString() =>
      'SportsWatchOptions(guide: ${guide.length}, '
      'possible: ${possible.length})';
}
