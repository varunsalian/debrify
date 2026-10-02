import 'dart:io' show Platform;
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../settings_summaries.dart';

class SettingsLeafBuilder {
  SettingsLeafBuilder(this.summaries, this.deps)
    : pageOpeners = <String, Future<void> Function()>{
        'Torbox': deps.openTorboxSettings,
        'Premiumize': deps.openPremiumizeSettings,
        'Real Debrid': deps.openRealDebridSettings,
        'AllDebrid': deps.openAllDebridSettings,
        'PikPak': deps.openPikPakSettings,
        'WebDAV': deps.openWebDavSettings,
        'Indexer Managers': deps.openIndexerManagersSettings,
        'Engines': deps.openTorrentSettings,
        'Filters': deps.openFilterSettings,
        'Default Provider': deps.openProviderSettings,
        'Quick Play': deps.openQuickPlaySettings,
        'Home Screen': deps.openHomePageSettings,
        'Launch Animation': deps.openLaunchAnimationPage,
        'Advanced': deps.openThemeTokensPage,
        'Sidebar': deps.openSidebarCustomization,
        'Profile Picker': deps.openProfileAppearance,
        'Playback': deps.openExternalPlayerSettings,
        'Debrify TV': deps.openDebrifyTvSettings,
        'Stremio TV': deps.openStremioTvSettings,
        'IPTV Playlists': deps.openIptvSettings,
        'Recordings': deps.openRecordings,
        'Trakt': deps.openTraktSettings,
        'Tracking': deps.openTrackingSettings,
        'Simkl': deps.openSimklSettings,
        'MDBList': deps.openMdblistSettings,
        'Profiles': deps.switchProfile,
        'Remote': deps.openRemoteControl,
      };
  final SettingsSummaries summaries;
  final ({
    BuildContext Function() context,
    bool Function() customPlayerCommandSupported,
    Future<bool> Function(ProfileFeature feature) ensureProfileFeature,
    bool Function() isAndroid,
    bool Function() isPhone,
    bool Function() isTelevision,
    bool Function() mounted,
    Future<void> Function() openAllDebridSettings,
    Future<void> Function() openDebrifyTvSettings,
    Future<void> Function() openExternalPlayerSettings,
    Future<void> Function() openFilterSettings,
    Future<void> Function() openHomePageSettings,
    Future<void> Function() openIndexerManagersSettings,
    Future<void> Function() openIptvAddSource,
    Future<void> Function() openIptvChannelOrder,
    Future<void> Function() openIptvSettings,
    Future<void> Function() openLaunchAnimationPage,
    Future<void> Function() openMdblistSettings,
    Future<void> Function() openPikPakSettings,
    Future<void> Function(PlaybackSettingsSection section) openPlaybackSection,
    Future<void> Function() openPremiumizeSettings,
    Future<void> Function() openProfileAppearance,
    Future<void> Function() openProviderSettings,
    Future<void> Function() openQuickPlaySettings,
    Future<void> Function() openRealDebridSettings,
    Future<void> Function() openRecordings,
    Future<void> Function() openRemoteControl,
    Future<void> Function() openSidebarCustomization,
    Future<void> Function() openSimklSettings,
    Future<void> Function() openStremioTvSettings,
    Future<void> Function() openThemeTokensPage,
    Future<void> Function() openTorboxSettings,
    Future<void> Function() openTorrentSettings,
    Future<void> Function() openTrackingSettings,
    Future<void> Function() openTraktSettings,
    Future<void> Function() openWebDavSettings,
    bool Function() preferredExternalPlayerSupported,
    bool Function() recordingSupported,
    Future<void> Function() switchProfile,
  })
  deps;

  static const pageIcons = <String, IconData>{
    'Torbox': Icons.link_rounded,
    'Premiumize': Icons.link_rounded,
    'Real Debrid': Icons.link_rounded,
    'AllDebrid': Icons.link_rounded,
    'PikPak': Icons.link_rounded,
    'WebDAV': Icons.cloud_rounded,
    'Indexer Managers': Icons.manage_search_rounded,
    'Engines': Icons.search_rounded,
    'Filters': Icons.filter_list_rounded,
    'Default Provider': Icons.cloud_sync_rounded,
    'Quick Play': Icons.bolt_rounded,
    'Home Screen': Icons.home_rounded,
    'Launch Animation': Icons.animation_rounded,
    'Advanced': Icons.tune_rounded,
    'Sidebar': Icons.view_sidebar_rounded,
    'Profile Picker': Icons.switch_account_rounded,
    'Playback': Icons.open_in_new_rounded,
    'Debrify TV': Icons.live_tv_rounded,
    'Stremio TV': Icons.smart_display_rounded,
    'IPTV Playlists': Icons.playlist_play_rounded,
    'Recordings': Icons.fiber_dvr_rounded,
    'Trakt': Icons.sync_rounded,
    'Tracking': Icons.sync_alt_rounded,
    'Simkl': Icons.sync_rounded,
    'MDBList': Icons.list_alt_rounded,
    'Profiles': Icons.people_alt_rounded,
    'Remote': Icons.phonelink_rounded,
  };

  final Map<String, Future<void> Function()> pageOpeners;

  SettingsSearchEntry leaf(
    String page,
    String title,
    String subtitle,
    List<String> keywords, {
    // Overrides the page's opener for a leaf that wants a deeper landing
    // (the add-source form rather than the IPTV page's default view).
    Future<void> Function()? onTap,
  }) => SettingsSearchEntry(
    icon: pageIcons[page]!,
    title: title,
    subtitle: subtitle,
    category: page,
    keywords: keywords,
    onTap: onTap ?? pageOpeners[page]!,
  );

  List<String> optionLabels(Iterable<String> values) => [
    for (final value in values) value.toLowerCase(),
  ];

  List<String> externalPlayerLabels() {
    if (kIsWeb) return const [];
    if (Platform.isMacOS) {
      return optionLabels(
        ExternalPlayer.values.map((player) => player.displayName),
      );
    }
    if (Platform.isLinux) {
      return optionLabels(
        LinuxExternalPlayer.values.map((player) => player.displayName),
      );
    }
    if (Platform.isWindows) {
      return optionLabels(
        WindowsExternalPlayer.values.map((player) => player.displayName),
      );
    }
    if (Platform.isIOS) {
      return optionLabels(
        iOSExternalPlayer.values
            .where((player) => !PlatformUtil.isTvOS || player.availableOnTvos)
            .map((player) => player.displayName),
      );
    }
    return const [];
  }

  static const audioLanguageLabels = [
    'no preference',
    'english',
    'spanish',
    'french',
    'german',
    'italian',
    'portuguese',
    'russian',
    'japanese',
    'korean',
    'chinese',
    'arabic',
    'hindi',
    'telugu',
    'dutch',
    'polish',
    'turkish',
    'swedish',
    'danish',
    'norwegian',
    'finnish',
  ];

  static const subtitleLanguageLabels = [
    ...audioLanguageLabels,
    'portuguese brazil',
    'brazilian portuguese',
    'pt-br',
    'off',
    'estonian',
    'croatian',
    'serbian',
    'bosnian',
    'macedonian',
    'slovenian',
    'czech',
    'slovak',
    'hungarian',
    'romanian',
    'bulgarian',
    'ukrainian',
    'greek',
    'latvian',
    'lithuanian',
    'hebrew',
    'persian',
    'thai',
    'vietnamese',
    'indonesian',
    'malay',
    'bengali',
    'tamil',
    'marathi',
    'gujarati',
    'kannada',
    'malayalam',
    'punjabi',
  ];

  static const advancedAppearanceOptions =
      <({String title, String subtitle, List<String> keywords})>[
        (
          title: 'Accent',
          subtitle: 'The colour used to mean “this one”',
          keywords: ['color', 'colour', 'theme', 'selected'],
        ),
        (
          title: 'Focus',
          subtitle: 'The colour of the cursor',
          keywords: ['cursor', 'focus color', 'focus colour', 'dpad'],
        ),
        (
          title: 'Progress',
          subtitle: 'Progress bars and watched marks',
          keywords: ['watched', 'marks', 'bar', 'state', 'colour', 'color'],
        ),
        (
          title: 'Callout',
          subtitle: 'Badges and highlights',
          keywords: ['badge', 'highlight', 'colour', 'color'],
        ),
        (
          title: 'Background',
          subtitle: 'The page behind everything',
          keywords: ['ground', 'surface', 'page', 'colour', 'color'],
        ),
        (
          title: 'Text',
          subtitle: 'The ink drawn over the background',
          keywords: ['ink', 'foreground', 'readability', 'colour', 'color'],
        ),
        (
          title: 'Corners',
          subtitle: 'How round cards are',
          keywords: ['radius', 'round', 'square', 'shape', 'cards'],
        ),
        (
          title: 'Buttons',
          subtitle: 'How round buttons and pills are',
          keywords: ['pill radius', 'round', 'square', 'shape'],
        ),
        (
          title: 'Titles',
          subtitle: 'The font used for display titles',
          keywords: ['display font', 'typeface', 'typography'],
        ),
        (
          title: 'Body',
          subtitle: 'The font used for everything else',
          keywords: ['body font', 'typeface', 'typography'],
        ),
        (
          title: 'Cursor',
          subtitle: 'How a focused item is expressed',
          keywords: [
            'focus expression',
            'ring',
            'scale',
            'lift',
            'invert',
            'flood',
            'parallax',
          ],
        ),
        (
          title: 'Character',
          subtitle: 'The tempo of app motion',
          keywords: ['motion', 'animation', 'standard', 'snap', 'glide'],
        ),
        (
          title: 'Entrances',
          subtitle: 'How new content arrives',
          keywords: ['motion', 'animation', 'transition'],
        ),
        (
          title: 'When idle',
          subtitle: 'What happens when interaction stops',
          keywords: ['idle policy', 'motion', 'animation'],
        ),
        (
          title: 'Separation',
          subtitle: 'How one surface is distinguished from another',
          keywords: ['space', 'rule', 'glass', 'fill', 'panel', 'surface'],
        ),
        (
          title: 'Scrims',
          subtitle: 'The fade behind text on artwork',
          keywords: ['scrim', 'gradient', 'artwork', 'readability'],
        ),
        (
          title: 'Frames',
          subtitle: 'How posters are edged',
          keywords: ['artwork', 'poster', 'border', 'frame'],
        ),
        (
          title: 'Grade',
          subtitle: 'Colour treatment over artwork',
          keywords: ['artwork', 'color grade', 'colour grade', 'filter'],
        ),
        (
          title: 'Room colour',
          subtitle: 'How much the page borrows from selected artwork',
          keywords: ['reactive room', 'artwork', 'ambient', 'color', 'colour'],
        ),
        (
          title: 'Accent from artwork',
          subtitle: 'Let poster colour replace the app accent',
          keywords: ['artwork accent', 'poster', 'dynamic color', 'colour'],
        ),
        (
          title: 'Film grain',
          subtitle: 'Texture layered over the interface',
          keywords: ['grain', 'noise', 'texture', 'cinema'],
        ),
        (
          title: 'Sheen',
          subtitle: 'Highlight along the top of a surface',
          keywords: ['texture', 'highlight', 'surface'],
        ),
        (
          title: 'Vignette',
          subtitle: 'Darkening toward the screen edges',
          keywords: ['texture', 'dark edges', 'artwork'],
        ),
        (
          title: 'Focus glow',
          subtitle: 'Halo around the cursor',
          keywords: ['bloom', 'glow', 'focus', 'cursor', 'halo'],
        ),
        (
          title: 'Sound and haptics',
          subtitle: 'What a press feels and sounds like',
          keywords: ['feedback', 'sound', 'haptic', 'vibration'],
        ),
        (
          title: 'While loading',
          subtitle: 'How not-yet-arrived content appears',
          keywords: ['skeleton', 'loading', 'placeholder', 'shimmer'],
        ),
      ];
}
