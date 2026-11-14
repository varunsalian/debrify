import 'package:debrify/features/sports/application/sports_reminder_plan.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/models/sports_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 8, 12);

SportsReminder _r(String key, Duration fromNow, {String league = 'EPL'}) =>
    SportsReminder(
      eventKey: key,
      start: _now.add(fromNow),
      title: 'Game $key',
      league: league,
    );

SportsEvent _event(
  String id, {
  Duration fromNow = const Duration(hours: 2),
  SportsEventStatus status = SportsEventStatus.scheduled,
  String title = 'Game',
}) => SportsEvent(
  id: id,
  leagueId: 'epl',
  start: _now.add(fromNow),
  status: status,
  title: title,
);

void main() {
  group('planSportsReminderAlerts', () {
    test('fires 15 minutes before kick-off with the league in the body', () {
      final alerts = planSportsReminderAlerts([
        _r('epl:1', const Duration(hours: 1)),
      ], _now);
      expect(alerts.single.id, 'epl:1');
      expect(alerts.single.fireAt, _now.add(const Duration(minutes: 45)));
      expect(alerts.single.title, 'Game epl:1');
      expect(alerts.single.body, 'Starts in 15 minutes · EPL');
    });

    test('a reminder whose fire time has passed is not scheduled', () {
      final alerts = planSportsReminderAlerts([
        _r('epl:soon', const Duration(minutes: 10)),
        _r('epl:past', const Duration(hours: -1)),
        _r('epl:later', const Duration(hours: 3)),
      ], _now);
      expect(alerts.map((a) => a.id), ['epl:later']);
    });

    test('keeps only the soonest alerts under the iOS pending limit', () {
      final reminders = [
        for (var i = 100; i > 0; i--)
          _r('epl:$i', Duration(hours: i), league: ''),
      ];
      final alerts = planSportsReminderAlerts(reminders, _now);
      expect(alerts, hasLength(sportsReminderMaxScheduled));
      expect(alerts.first.id, 'epl:1');
      expect(alerts.last.id, 'epl:$sportsReminderMaxScheduled');
      expect(alerts.first.body, 'Starts in 15 minutes');
    });
  });

  group('sportsReminderAvailable', () {
    test('only for a scheduled game more than the lead time away', () {
      expect(sportsReminderAvailable(_event('a'), _now), isTrue);
      expect(
        sportsReminderAvailable(
          _event('b', fromNow: const Duration(minutes: 15)),
          _now,
        ),
        isFalse,
      );
      expect(
        sportsReminderAvailable(
          _event('c', status: SportsEventStatus.live),
          _now,
        ),
        isFalse,
      );
    });
  });

  test('reminders more than six hours past kick-off are dropped', () {
    final due = sportsRemindersStillDue([
      _r('epl:old', const Duration(hours: -7)),
      _r('epl:recent', const Duration(hours: -5)),
      _r('epl:next', const Duration(hours: 5)),
    ], _now);
    expect(due.map((r) => r.eventKey), ['epl:recent', 'epl:next']);
  });

  group('reconcileSportsReminders', () {
    final reminders = [
      SportsReminder(
        eventKey: 'epl:1',
        start: _now.add(const Duration(hours: 2)),
        title: 'Game',
        league: 'EPL',
      ),
      SportsReminder(
        eventKey: 'epl:2',
        start: _now.add(const Duration(hours: 3)),
        title: 'Game',
        league: 'EPL',
      ),
    ];

    test('null when the board shows nothing new', () {
      expect(reconcileSportsReminders(reminders, [_event('1')]), isNull);
      expect(reconcileSportsReminders(reminders, const []), isNull);
      expect(reconcileSportsReminders(const [], [_event('1')]), isNull);
    });

    test('a moved kick-off moves its reminder and keeps the others', () {
      final next = reconcileSportsReminders(reminders, [
        _event('1', fromNow: const Duration(hours: 4)),
      ])!;
      expect(next.first.start, _now.add(const Duration(hours: 4)));
      expect(next.first.league, 'EPL');
      expect(next.last, reminders.last);
    });

    test('a postponed or finished game drops its reminder', () {
      final next = reconcileSportsReminders(reminders, [
        _event('1', status: SportsEventStatus.postponed),
        _event('2', status: SportsEventStatus.finished),
      ])!;
      expect(next, isEmpty);
    });
  });

  test('a reminder survives encoding, and junk decodes to null', () {
    final reminder = _r('epl:1', const Duration(hours: 1));
    expect(SportsReminder.decode(reminder.encode()), reminder);
    expect(SportsReminder.decode('not json'), isNull);
    expect(SportsReminder.decode('{"key":"x"}'), isNull);
    expect(SportsReminder.decode('[1,2]'), isNull);
  });
}
