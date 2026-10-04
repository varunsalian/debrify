import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';

typedef PlaybackSubtitleSectionDependencies = ({PlaybackSubtitleState sub});

class PlaybackSubtitleSection {
  final PlaybackSubtitleSectionDependencies _deps;
  PlaybackSubtitleSection(this._deps);

  // Subtitle language options: (code, label)
  static const List<(String?, String)> subtitleLanguageOptions = [
    (null, 'No Preference'),
    ('off', 'Off'),
    ('en', 'English'),
    ('es', 'Spanish'),
    ('fr', 'French'),
    ('de', 'German'),
    ('it', 'Italian'),
    ('pt', 'Portuguese'),
    ('pt-BR', 'Portuguese (Brazil)'),
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
    ('et', 'Estonian'),
    ('hr', 'Croatian'),
    ('sr', 'Serbian'),
    ('bs', 'Bosnian'),
    ('mk', 'Macedonian'),
    ('sl', 'Slovenian'),
    ('cs', 'Czech'),
    ('sk', 'Slovak'),
    ('hu', 'Hungarian'),
    ('ro', 'Romanian'),
    ('bg', 'Bulgarian'),
    ('uk', 'Ukrainian'),
    ('el', 'Greek'),
    ('lv', 'Latvian'),
    ('lt', 'Lithuanian'),
    ('he', 'Hebrew'),
    ('fa', 'Persian'),
    ('th', 'Thai'),
    ('vi', 'Vietnamese'),
    ('id', 'Indonesian'),
    ('ms', 'Malay'),
    ('bn', 'Bengali'),
    ('ta', 'Tamil'),
    ('mr', 'Marathi'),
    ('gu', 'Gujarati'),
    ('kn', 'Kannada'),
    ('ml', 'Malayalam'),
    ('pa', 'Punjabi'),
  ];

  int get subtitleLanguageIndex {
    final idx = subtitleLanguageOptions.indexWhere(
      (opt) => opt.$1 == _deps.sub.defaultSubtitleLanguage,
    );
    return idx >= 0 ? idx : 0;
  }
}
