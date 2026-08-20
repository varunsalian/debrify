import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cinema Zoom is appended without changing persisted mode indexes', () {
    expect(AspectMode.contain.index, 0);
    expect(AspectMode.aspect5_4.index, 9);
    expect(AspectMode.cinemaZoom.index, 10);
  });

  test('Cinema Zoom round-trips through resume storage', () {
    expect(
      AspectModeUtils.aspectModeToString(AspectMode.cinemaZoom),
      'cinemaZoom',
    );
    expect(
      AspectModeUtils.stringToAspectMode('cinemaZoom'),
      AspectMode.cinemaZoom,
    );
  });

  test('Cinema Zoom defaults remain portable with a profile', () {
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'player_default_aspect_index',
        10,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'player_default_aspect_index_tv',
        3,
      ),
      isTrue,
    );
  });

  test(
    'Cinema Zoom preserves aspect while scaling the picture by four thirds',
    () {
      expect(
        AspectModeUtils.getBoxFitForMode(AspectMode.cinemaZoom),
        BoxFit.contain,
      );
      expect(
        AspectModeUtils.getScaleForMode(AspectMode.cinemaZoom),
        closeTo(4 / 3, 0.000001),
      );
      expect(AspectModeUtils.getScaleForMode(AspectMode.cover), 1.0);
    },
  );
}
