import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';

typedef PlaybackVideoSectionDependencies = ({PlaybackValuesState values});

class PlaybackVideoSection {
  final PlaybackVideoSectionDependencies _deps;
  PlaybackVideoSection(this._deps);

  // Aspect labels
  List<String> get aspectLabels => _deps.values.isAndroidTv
      ? ['Fit', 'Fill', 'Zoom', 'Cinema Zoom']
      : [
          'Contain',
          'Cover',
          'Fit Width',
          'Fit Height',
          '16:9',
          '4:3',
          '21:9',
          '1:1',
          '3:2',
          '5:4',
          'Cinema Zoom',
        ];
}
