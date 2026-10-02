import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/video_player/services/network_tuning.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice06 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice6() {
    return [
      // Player Settings
      leaf(
        'Playback',
        'Default Player',
        'Which player plays videos',
        const [
          'default player',
          'debrify player',
          'external',
          'external player',
          'built-in',
          'system app chooser',
          'deovr',
        ],
        onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Default Subtitle language',
        'Preferred subtitle language',
        const [
          'subtitle',
          'subtitles',
          'language',
          'captions',
          ...SettingsLeafBuilder.subtitleLanguageLabels,
        ],
        onTap: () =>
            deps.openPlaybackSection(PlaybackSettingsSection.subtitles),
      ),
      leaf(
        'Playback',
        'Default Audio language',
        'Preferred audio language / track',
        const [
          'audio',
          'language',
          'track',
          'dub',
          ...SettingsLeafBuilder.audioLanguageLabels,
        ],
        onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.audio),
      ),
      leaf(
        'Playback',
        'Subtitle Appearance',
        'Subtitle size, style, color, background & font',
        [
          'subtitle',
          'size',
          'style',
          'color',
          'background',
          'font',
          'bold',
          'outline',
          'captions',
          ...optionLabels(SubtitleSize.options.map((option) => option.label)),
          ...optionLabels(SubtitleStyle.options.map((option) => option.label)),
          ...optionLabels(SubtitleColor.options.map((option) => option.label)),
          ...optionLabels(
            SubtitleBackground.options.map((option) => option.label),
          ),
          ...optionLabels(
            SubtitleFont.builtInOptions.map((option) => option.label),
          ),
        ],
        onTap: () =>
            deps.openPlaybackSection(PlaybackSettingsSection.subtitles),
      ),
      leaf(
        'Playback',
        'Default Aspect Ratio',
        'Default video aspect / zoom',
        const [
          'aspect',
          'ratio',
          'zoom',
          'cinema zoom',
          'fit',
          'fill',
          'contain',
          'cover',
          'fit width',
          'fit height',
          '16:9',
          '4:3',
          '21:9',
          '1:1',
          '3:2',
          '5:4',
        ],
        onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.video),
      ),
      leaf(
        'Playback',
        'Watch completion thresholds',
        'Choose when locally tracked movies and episodes are marked watched',
        const [
          'watch history',
          'watched',
          'completion',
          'threshold',
          'movie',
          'episode',
          'series',
          'percentage',
          'percent',
          'rewatch',
        ],
        onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Skip intros & credits',
        'Show manual skip buttons when timestamps are available',
        const [
          'skip intro',
          'skip credits',
          'outro',
          'opening',
          'ending',
          'skip segment',
        ],
        onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Timestamp provider',
        'Choose the source for intro and outro timestamps',
        const [
          'auto',
          'skipdb',
          'introdb',
          'theintrodb',
          'provider',
          'timestamp',
          'segments',
        ],
        onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Network & Buffering',
        'Connection patience & stream buffer for slow sources',
        [
          'network',
          'buffer',
          'buffering',
          'cache',
          'timeout',
          'plex',
          'slow',
          'stall',
          'patience',
          'auto-retry',
          'read-ahead',
          ...optionLabels(NetworkTuning.patienceOptions.values),
          ...optionLabels(NetworkTuning.bufferOptions.values),
        ],
        onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
      ),
    ];
  }
}
