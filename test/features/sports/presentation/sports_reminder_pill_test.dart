// The "Remind me" control and the card's reminder bell.
import 'package:debrify/features/sports/application/sports_reminders_notifier.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_event_card.dart';
import 'package:debrify/features/sports/presentation/sports_event_details.dart';
import 'package:debrify/features/sports/presentation/sports_reminder_pill.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2030, 1, 5, 15);

SportsEvent _game() => SportsEvent(
  id: 'e1',
  leagueId: 'epl',
  start: _start,
  status: SportsEventStatus.scheduled,
  home: const SportsTeam(
    id: '1',
    name: 'Arsenal',
    shortName: 'Arsenal',
    abbreviation: 'ARS',
  ),
  away: const SportsTeam(
    id: '2',
    name: 'Spurs',
    shortName: 'Spurs',
    abbreviation: 'TOT',
  ),
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 380, child: child)),
  ),
);

Finder get _pill => find.byKey(const ValueKey('sports-details-reminder'));

void main() {
  testWidgets('tapping sets and clears the reminder', (tester) async {
    final outcomes = [SportsReminderToggle.added, SportsReminderToggle.removed];
    var calls = 0;
    await tester.pumpWidget(
      _host(
        SportsReminderPill(
          control: (on: false, toggle: () async => outcomes[calls++]),
        ),
      ),
    );
    expect(find.text('Remind me 15 min before'), findsOneWidget);
    await tester.tap(_pill);
    await tester.pumpAndSettle();
    expect(find.text('Reminder set · 15 min before'), findsOneWidget);
    await tester.tap(_pill);
    await tester.pumpAndSettle();
    expect(find.text('Remind me 15 min before'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a refused permission explains how to turn it on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SportsReminderPill(
          control: (
            on: false,
            toggle: () async => SportsReminderToggle.permissionDenied,
          ),
        ),
      ),
    );
    await tester.tap(_pill);
    await tester.pumpAndSettle();
    expect(find.text(sportsReminderPermissionCopy), findsOneWidget);
    expect(find.text('Remind me 15 min before'), findsOneWidget);
  });

  testWidgets('a toggle that throws explains and stays usable', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        SportsReminderPill(
          control: (
            on: false,
            toggle: () async {
              calls++;
              if (calls == 1) throw StateError('channel failed');
              return SportsReminderToggle.added;
            },
          ),
        ),
      ),
    );
    await tester.tap(_pill);
    await tester.pumpAndSettle();
    expect(find.text(sportsReminderFailedCopy), findsOneWidget);
    await tester.tap(_pill);
    await tester.pumpAndSettle();
    expect(find.text('Reminder set · 15 min before'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('the details panel offers it only when given a control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> open(SportsReminderControl? reminder) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSportsEventDetails(
                context,
                event: _game(),
                watch: const SportsWatchOptions(),
                follows: const SportsFollows(),
                onPlay: (_) {},
                onToggleTeam: (_) {},
                onToggleLeague: (_) {},
                reminder: reminder,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open(null);
    expect(_pill, findsNothing);
    await tester.tap(find.byKey(const ValueKey('sports-details-close')));
    await tester.pumpAndSettle();
    await open((on: true, toggle: () async => SportsReminderToggle.removed));
    expect(find.text('Reminder set · 15 min before'), findsOneWidget);
  });

  testWidgets('a card with a reminder says so', (tester) async {
    await tester.pumpWidget(
      _host(
        SportsEventCard(
          event: _game(),
          hideScores: false,
          followed: false,
          reminded: true,
          watch: const SportsWatchOptions(),
          onPressed: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Reminder set')), findsOneWidget);
  });
}
