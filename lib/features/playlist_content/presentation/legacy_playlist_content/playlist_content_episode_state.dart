import 'dart:async';

class PlaylistContentEpisodeState {
  // Long-press state for episode cards (Android TV D-pad)
  Timer? episodeLongPressTimer;

  bool episodeLongPressTriggered = false;

  DateTime? lastEpisodeLongPressTime;

  bool episodeKeyDownReceived = false;

  bool isAndroidTv = false;
}
