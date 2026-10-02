import 'package:debrify/screens/settings/debrify_tv_player_style_page.dart';
import 'package:debrify/screens/settings/debrify_tv_style_page.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart';
import 'package:debrify/screens/settings/play_loader_style_page.dart';
import 'package:debrify/screens/settings/player_dock_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/tv_player_controls_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/utils/platform_util.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice06 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice6() {
    return [
      // Gated like the IPTV section itself: the picker only matters where
      // the cockpit renders (Android TV, desktop). Lands on the picker.
      if (deps.iptvAppearanceSearchable())
        nav(
          SettingsRows.iptvAppearance,
          'Appearance',
          deps.openIptvStylePage,
          subtitle: iptvStyleLabel(summaries.iptvStyle),
          keywords: [
            'iptv',
            'style',
            'theme',
            'look',
            'skin',
            'appearance',
            'command center',
            'first edition',
            'master control',
            'spotlight guide',
            'apple tv',
            'epg',
            'cockpit',
            'premium',
            'live tv',
            'dvr',
            'live tv & dvr',
            ...labels(kIptvStyleChoices.map((choice) => choice.label)),
          ],
        ),
      // Ungated: the pref covers every device class — the Spotlight arm has
      // a TV layout AND a phone layout. Lands on the picker.
      nav(
        SettingsRows.debrifyTvAppearance,
        'Appearance',
        deps.openDebrifyTvStylePage,
        subtitle: debrifyTvStyleLabel(summaries.debrifyTvStyle),
        keywords: [
          'debrify tv',
          'channels',
          'channel grid',
          'rail',
          'stage',
          'spotlight',
          'style',
          'layout',
          'look',
          'appearance',
          ...labels(kDebrifyTvStyleChoices.map((choice) => choice.label)),
        ],
      ),
      // Ungated: every platform has a player — phones use the Dart player,
      // Android TV the native one, and both read the pref. Lands on the
      // picker.
      nav(
        SettingsRows.playerGuideStyle,
        'Appearance',
        deps.openPlayerGuideStylePage,
        subtitle: playerGuideStyleLabel(summaries.playerGuideStyle),
        keywords: [
          'iptv',
          'player',
          'guide',
          'zap',
          'banner',
          'style',
          'theme',
          'look',
          'skin',
          'cinema glass',
          'midnight edition',
          'master control',
          'classic',
          'live tv',
          'dvr',
          'live tv & dvr',
          ...labels(
            playerGuideStyleChoicesForPlatform().map((choice) => choice.label),
          ),
        ],
      ),
      // Ungated — every platform shows a loader between Play and the
      // picture. Lands on the picker.
      nav(
        SettingsRows.playLoaderStyle,
        'Appearance',
        deps.openPlayLoaderStylePage,
        subtitle: playLoaderStyleLabel(summaries.playLoaderStyle),
        keywords: [
          'play',
          'loading',
          'loader',
          'spinner',
          'searching',
          'resolving',
          'progress',
          'marquee',
          'backdrop',
          'logo',
          'stages',
          'pipeline',
          ...labels(
            PlayLoaderStyleController.options.map((choice) => choice.label),
          ),
        ],
      ),
      // Android TV only: the skin picker for the NATIVE player's controls.
      // tvOS runs the Flutter player (one look) and phones/desktops have the
      // dock row below instead. PlatformUtil, not _isAndroidTv — the latter
      // answers the form-factor question and is true on Apple TV.
      if (PlatformUtil.isAndroidTvCached)
        nav(
          SettingsRows.tvPlayerControls,
          'Appearance',
          deps.openTvPlayerControlsStylePage,
          subtitle: tvPlayerControlsStyleLabel(summaries.tvPlayerControlsStyle),
          keywords: [
            'player',
            'controls',
            'dock',
            'buttons',
            'seekbar',
            'scrubber',
            'transport',
            'ott',
            'legacy',
            'cinema',
            'style',
            'look',
            'skin',
            ...labels(
              kTvPlayerControlsStyleChoices.map((choice) => choice.label),
            ),
          ],
        ),
      // Android TV only: the Debrify TV playback-screen style (native
      // TorboxTvPlayerActivity is the pref's only reader).
      if (PlatformUtil.isAndroidTvCached)
        nav(
          SettingsRows.debrifyTvPlayer,
          'Appearance',
          deps.openDebrifyTvPlayerStylePage,
          subtitle: debrifyTvPlayerStyleLabel(summaries.debrifyTvPlayerStyle),
          keywords: [
            'debrify tv',
            'magic tv',
            'channel',
            'player',
            'network',
            'cinema',
            'guide',
            'spotlight',
            'prestige',
            'badge',
            'quality',
            'style',
            'look',
            'skin',
            ...labels(
              kDebrifyTvPlayerStyleChoices.map((choice) => choice.label),
            ),
          ],
        ),
      if (!PlatformUtil.isTelevision)
        nav(
          SettingsRows.playerDock,
          'Appearance',
          deps.openPlayerDockPage,
          subtitle: playerDockLabel(
            summaries.playerDockStyle,
            summaries.playerDockPalette,
            summaries.playerDockSize,
          ),
          keywords: [
            'player',
            'controls',
            'dock',
            'buttons',
            'seekbar',
            'scrubber',
            'size',
            'colour',
            'color',
            'palette',
            'style',
            'look',
            'big',
            'small',
            'layout',
            'accent',
            ...labels(kPlayerDockStyleChoices.map((choice) => choice.label)),
            ...labels(kPlayerDockPaletteChoices.map((choice) => choice.label)),
            ...labels(kPlayerDockSizeChoices.map((choice) => choice.label)),
          ],
        ),
    ];
  }
}
