import 'package:debrify/screens/video_player_screen.dart';

import 'debrify_tv_handoff.dart';

/// [site] built [player] from exactly [supplied]; every other field keeps the
/// constructor default.
void expectStremioTvPlayer(
  VideoPlayerScreen player,
  String site,
  Map<String, Object?> supplied,
) => expectDebrifyTvPlayer(player, site, supplied);
