// The network share on the Recordings page: the status row that leads to its
// settings, and the share's recordings listed, played and deleted.
import 'package:debrify/features/recording_output/models/share_recording.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/screens/settings/recording_output_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';

final _golf = ShareRecording(
  name: 'UK SKY SPORT GOLF 2026-10-30.ts',
  path: 'Rec/UK SKY SPORT GOLF 2026-10-30.ts',
  bytes: 31 * 1024 * 1024,
  modified: DateTime(2026, 10, 30, 12, 31),
);
final _news = ShareRecording(
  name: 'Sky Sports News.ts',
  path: 'Rec/Sky Sports News.ts',
  bytes: 2 * 1024 * 1024 * 1024,
  modified: DateTime(2026, 10, 29, 20, 5),
);

final class _Share {
  ShareLibrary? library = ShareLibrary(
    address: r'\\192.168.29.232\Recordings',
    recordsDirect: true,
    recordings: [_golf, _news],
  );
  int loads = 0;
  int settingsOpened = 0;
  final played = <ShareRecording>[];
  final deleted = <ShareRecording>[];

  RecordingsHubShare access() => RecordingsHubShare(
    load: () async {
      loads++;
      return library;
    },
    streamUrl: (recording) async {
      played.add(recording);
      // Stops short of launching the player, which this test does not need.
      throw StateError('no player in this test');
    },
    delete: (recording) async {
      deleted.add(recording);
      final current = library!;
      library = ShareLibrary(
        address: current.address,
        recordsDirect: current.recordsDirect,
        recordings: [
          for (final r in current.recordings)
            if (r != recording) r,
        ],
      );
    },
    openSettings: () async => settingsOpened++,
  );
}

void main() {
  late _Share share;

  setUp(() {
    share = _Share();
    debugRecordingsHubShare = (_) => share.access();
  });
  tearDown(() => debugRecordingsHubShare = null);

  testWidgets('the share and its recordings are listed', (t) async {
    await recordingsCase(t, (f) async {
      await f.mount(t);
      await f.until(t, () => find.text('ON YOUR SHARE').evaluate().isNotEmpty);

      expect(find.text('Recording to your network share'), findsOneWidget);
      expect(find.text(r'\\192.168.29.232\Recordings'), findsOneWidget);
      expect(find.text('UK SKY SPORT GOLF 2026-10-30'), findsOneWidget);
      expect(find.text('Sky Sports News'), findsOneWidget);
      expect(
        find.textContaining('2 · 2'),
        findsOneWidget,
        reason: 'count · size',
      );
      expect(find.text('ON THIS DEVICE'), findsOneWidget);
      expect(
        find.text(r'New recordings are saved to \\192.168.29.232\Recordings'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the status row opens the share settings', (t) async {
    await recordingsCase(t, (f) async {
      await f.mount(t);
      await f.until(t, () => find.text('Change').evaluate().isNotEmpty);
      final loadsBefore = share.loads;

      await t.tap(find.text('Change'));
      await f.settle(t);

      expect(share.settingsOpened, 1);
      expect(share.loads, greaterThan(loadsBefore), reason: 'relisted after');
    });
  });

  testWidgets('without a share the row invites setting one up', (t) async {
    share.library = null;
    await recordingsCase(t, (f) async {
      await f.mount(t);
      await f.until(
        t,
        () => find
            .text('Save recordings to a network share')
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('Set up'), findsOneWidget);
      expect(find.text('ON YOUR SHARE'), findsNothing);
      expect(find.text('ON THIS DEVICE'), findsNothing);
    });
  });

  testWidgets('a share that cannot be read says so', (t) async {
    share.library = const ShareLibrary(
      address: r'\\nas\tv',
      recordsDirect: true,
      error: 'The share cannot be reached right now',
    );
    await recordingsCase(t, (f) async {
      await f.mount(t);
      await f.until(
        t,
        () => find
            .text(r'The share cannot be reached right now (\\nas\tv).')
            .evaluate()
            .isNotEmpty,
      );
    });
  });

  testWidgets('pressing a share recording asks the share for a stream', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await f.mount(t);
      await f.until(
        t,
        () => find.text('Sky Sports News').evaluate().isNotEmpty,
      );

      await t.tap(find.text('Sky Sports News'));
      await f.settle(t);

      expect(share.played, [_news]);
      expect(find.text("Couldn't open the network share"), findsOneWidget);
    });
  });

  testWidgets('deleting a share recording asks first, then relists', (t) async {
    await recordingsCase(t, (f) async {
      await f.mount(t);
      await f.until(
        t,
        () => find.text('UK SKY SPORT GOLF 2026-10-30').evaluate().isNotEmpty,
      );
      // The share's rows come first, newest first: this is the golf one.
      await t.tap(find.byTooltip('Delete recording').first);
      await f.settle(t);
      expect(
        find.textContaining(r'will be removed from \\192.168.29.232'),
        findsOneWidget,
      );

      await t.tap(find.text('Delete'));
      await f.until(
        t,
        () => find.text('UK SKY SPORT GOLF 2026-10-30').evaluate().isEmpty,
      );
      expect(share.deleted, [_golf]);
      expect(find.text('Sky Sports News'), findsOneWidget);
    });
  });
}
