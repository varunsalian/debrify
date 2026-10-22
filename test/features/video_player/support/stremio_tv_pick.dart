import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'player_actions.dart';
import 'video_player_environment.dart';

/// A two-channel Stremio TV directory whose switch provider is never called:
/// the tests pick through the guide sheet's own `onChannelSwitched`.
const stremioTvPickDirectory = [
  {'id': 'a', 'name': 'Alpha', 'channelNumber': 7, 'isCurrent': true},
  {'id': 'b', 'name': 'Beta', 'channelNumber': 9},
];

Future<Map<String, dynamic>?> stremioTvNoSwitch(String id) async => null;

/// Opens the Stremio TV guide from the touch controls and starts a channel
/// switch through the sheet's callback. Returns the switch's own Future
/// without waiting for it, so a caller can hold the switch mid-open.
Future<Future<dynamic>> beginStremioTvPick(
  WidgetTester t,
  VideoPlayerEnvironment f,
  String id, {
  String? url,
  String? title,
  T Function<T>(T Function() body)? observe,
}) async {
  final show = playerControls(t).onShowGuide;
  expect(show, isNotNull, reason: 'The player exposes its Stremio TV guide');
  show!();
  await f.until(
    t,
    () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
  );
  final dynamic callback = t
      .widget<StremioTvGuideSheet>(find.byType(StremioTvGuideSheet))
      .onChannelSwitched;
  dynamic start() => callback(
    id,
    url ?? 'https://stremio-pick.test/$id.mp4',
    title ?? 'Channel $id',
    contentType: 'movie',
  );
  final dynamic result = observe == null ? start() : observe(start);
  return result is Future ? result : Future<dynamic>.value(result);
}
