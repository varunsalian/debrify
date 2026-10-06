import 'package:debrify/widgets/iptv/iptv_startup_channel_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recordings_fixture.dart';

class RecordingsManualDriver {
  RecordingsManualDriver(this.tester, this.fixture);
  final WidgetTester tester;
  final RecordingsFixture fixture;
  final String url = 'http://recordings.test/manual.ts';

  Future<void> open({String? channelUrl}) async {
    await fixture.tap(tester, find.text('Schedule').first);
    await fixture.until(
      tester,
      () => find.text('Record which channel?').evaluate().isNotEmpty,
    );
    fixture.navigator.currentState!.pop(
      const IptvStartupChannelChoice(
        url: 'http://recordings.test/manual.ts',
        name: 'Manual channel',
        playlistId: null,
        channelNumber: 7,
        group: 'Group',
        logoUrl: null,
        httpHeaders: {'X-Fixture': 'manual'},
        connectionResourceId: null,
        connectionResourceRevision: null,
        listName: 'Favorites',
      ),
    );
    await fixture.settle(tester);
  }

  Future<void> date(DateTime value) async {
    await fixture.until(
      tester,
      () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
    );
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(
      picker.lastDate.difference(picker.firstDate).inDays,
      7,
      reason: 'manual date picker includes seventh day',
    );
    fixture.navigator.currentState!.pop(value);
    await fixture.settle(tester);
  }

  Future<void> time(TimeOfDay value) async {
    fixture.navigator.currentState!.pop(value);
    await fixture.settle(tester);
  }

  Future<void> length() async {
    await fixture.until(
      tester,
      () => find.text('Record for how long?').evaluate().isNotEmpty,
    );
    final labels = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((row) => (row.title! as Text).data)
        .toList();
    expect(labels, [
      '5 minutes (test)',
      '30 minutes',
      '1 hour',
      '2 hours',
      '3 hours',
      'Pick end time…',
    ], reason: 'duration presets retain order');
  }

  Future<void> untilLength({
    DateTime? day,
    TimeOfDay time = const TimeOfDay(hour: 12, minute: 0),
  }) async {
    await open();
    await date(day ?? DateTime.now().add(const Duration(days: 2)));
    await this.time(time);
    await length();
  }
}
