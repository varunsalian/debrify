import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_player_environment.dart';

Controls playerControls(WidgetTester tester) =>
    tester.widget<Controls>(find.byType(Controls));

Future<PlayerMenuPanel> openPlayerMenu(
  WidgetTester tester,
  VideoPlayerEnvironment fixture,
) async {
  playerControls(tester).onShowTracks();
  await fixture.advance(tester, const Duration(milliseconds: 300));
  return tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
}
