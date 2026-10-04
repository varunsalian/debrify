import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';

typedef PlaybackAudioSectionDependencies = ({PlaybackSubtitleState sub});

class PlaybackAudioSection {
  final PlaybackAudioSectionDependencies _deps;
  PlaybackAudioSection(this._deps);

  // Audio language options: (code, label) - no "Off" option for audio
  static const List<(String?, String)> audioLanguageOptions = [
    (null, 'No Preference'),
    ('en', 'English'),
    ('es', 'Spanish'),
    ('fr', 'French'),
    ('de', 'German'),
    ('it', 'Italian'),
    ('pt', 'Portuguese'),
    ('ru', 'Russian'),
    ('ja', 'Japanese'),
    ('ko', 'Korean'),
    ('zh', 'Chinese'),
    ('ar', 'Arabic'),
    ('hi', 'Hindi'),
    ('te', 'Telugu'),
    ('nl', 'Dutch'),
    ('pl', 'Polish'),
    ('tr', 'Turkish'),
    ('sv', 'Swedish'),
    ('da', 'Danish'),
    ('no', 'Norwegian'),
    ('fi', 'Finnish'),
  ];

  int get audioLanguageIndex {
    final idx = audioLanguageOptions.indexWhere(
      (opt) => opt.$1 == _deps.sub.defaultAudioLanguage,
    );
    return idx >= 0 ? idx : 0;
  }
}
