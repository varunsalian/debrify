// Kick-off reminders: what the user asked to be told about, and what the
// device is asked to show.
//
// Models layer: plain immutable values plus the platform contract. Storage,
// scheduling and permission prompts live behind [SportsReminderScheduler].
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'sports_models.dart';

/// One game the active profile asked to be reminded about.
@immutable
class SportsReminder {
  const SportsReminder({
    required this.eventKey,
    required this.start,
    required this.title,
    required this.league,
  });

  /// `'<leagueId>:<eventId>'`, unique across leagues.
  final String eventKey;

  /// Kick-off, always UTC.
  final DateTime start;

  /// e.g. `'Arsenal v Spurs'`.
  final String title;

  /// League name for the notification, e.g. `'Premier League'`.
  final String league;

  static String keyOf(SportsEvent event) => '${event.leagueId}:${event.id}';

  SportsReminder copyWith({DateTime? start, String? title}) => SportsReminder(
    eventKey: eventKey,
    start: start ?? this.start,
    title: title ?? this.title,
    league: league,
  );

  String encode() => jsonEncode({
    'key': eventKey,
    'start': start.toUtc().millisecondsSinceEpoch,
    'title': title,
    'league': league,
  });

  /// Null for anything that is not a reminder this version wrote.
  static SportsReminder? decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final key = map['key'];
      final start = map['start'];
      final title = map['title'];
      final league = map['league'];
      if (key is! String || key.isEmpty || start is! int || title is! String) {
        return null;
      }
      return SportsReminder(
        eventKey: key,
        start: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
        title: title,
        league: league is String ? league : '',
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsReminder &&
          other.eventKey == eventKey &&
          other.start == start &&
          other.title == title &&
          other.league == league);

  @override
  int get hashCode => Object.hash(eventKey, start, title, league);
}

/// One notification the device is asked to show at [fireAt].
@immutable
class SportsReminderAlert {
  const SportsReminderAlert({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  /// Stable per game, so a re-plan replaces rather than duplicates.
  final String id;

  /// UTC.
  final DateTime fireAt;
  final String title;
  final String body;

  Map<String, Object> toMap() => {
    'id': id,
    'fireAtMs': fireAt.toUtc().millisecondsSinceEpoch,
    'title': title,
    'body': body,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsReminderAlert &&
          other.id == id &&
          other.fireAt == fireAt &&
          other.title == title &&
          other.body == body);

  @override
  int get hashCode => Object.hash(id, fireAt, title, body);
}

/// The device side of reminders: notification permission and the set of
/// scheduled alerts.
abstract interface class SportsReminderScheduler {
  /// Phones and tablets only: TVs do not show app notifications.
  bool get isSupported;

  /// Asks for notification permission if needed. True when alerts will show.
  Future<bool> ensurePermission();

  /// Makes [alerts] the complete set of scheduled reminders, cancelling any
  /// scheduled earlier that are not in it.
  Future<void> replaceAll(List<SportsReminderAlert> alerts);
}
