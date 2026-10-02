import 'package:debrify/screens/settings/settings_spotlight_shell.dart';
import 'package:flutter/material.dart';

const List<SettingsCategoryDefinition> kAdaptiveSettingsCategories = [
  SettingsCategoryDefinition(
    icon: Icons.link_rounded,
    label: 'Connections',
    subtitle: 'Debrid, cloud, IPTV & more',
    eyebrow: 'Connections',
    title: 'Services, all in one place.',
    description:
        'See what is ready, what needs attention, and where playback will go '
        'before opening a provider.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.sync_rounded,
    label: 'Trackers',
    subtitle: 'Trakt & Simkl watch history',
    eyebrow: 'Trackers',
    title: 'Keep every watch in sync.',
    description:
        'Choose how tracking works, then connect each watch-history service '
        'without digging through account screens.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.home_rounded,
    label: 'Home & Display',
    subtitle: 'Rows, artwork & navigation',
    eyebrow: 'Home & Display',
    title: 'Shape the room you come home to.',
    description:
        'Arrange the home screen and choose the navigation that fits this '
        'device.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.collections_bookmark_rounded,
    label: 'Collections',
    subtitle: 'Import and manage folder collections',
    eyebrow: 'Collections',
    title: 'Collections',
    description: 'Import and manage folder collections.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.sell_rounded,
    label: 'Badges',
    subtitle: 'Import and manage stream badge rules',
    eyebrow: 'Badges',
    title: 'Badges',
    description: 'Import and manage stream badge rules.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.info_outline_rounded,
    label: 'Metadata',
    subtitle: 'Providers, artwork, languages & discovery',
    eyebrow: 'Metadata',
    title: 'Choose your metadata.',
    description:
        'Choose providers for title information, artwork and trailers, and set your preferred languages.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.auto_awesome_rounded,
    label: 'Appearance',
    subtitle: 'Look, text, motion & layouts',
    eyebrow: 'Appearance',
    title: 'Make the interface feel like yours.',
    description:
        'A Look sets the room. Individual controls below let you adjust only '
        'what matters.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.play_circle_outline_rounded,
    label: 'Playback',
    subtitle: 'Player, video, audio & subtitles',
    eyebrow: 'Playback',
    title: 'Playback without surprises.',
    description:
        'Choose how videos start, what plays them, and the behavior shared by '
        'movies and episodes.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.search_rounded,
    label: 'Search',
    subtitle: 'Engines, filters & providers',
    eyebrow: 'Search',
    title: 'Find the right source faster.',
    description:
        'Search engines, default filters, and provider routing form one clear '
        'pipeline.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.explore_rounded,
    label: 'Discover',
    subtitle: 'Source & poster cards',
    eyebrow: 'Discover',
    title: 'Open where you want to browse.',
    description:
        'Remember the last source you used or choose one source to show every '
        'time Discover opens.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.live_tv_rounded,
    label: 'Live TV & DVR',
    subtitle: 'Channels, guide & recordings',
    eyebrow: 'Live TV & DVR',
    title: 'Live television, organized.',
    description:
        'Manage channel sources, recordings, and the guide from one focused '
        'area.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.devices_rounded,
    label: 'Devices',
    subtitle: 'Remote & setup transfer',
    eyebrow: 'Devices',
    title: 'Let your devices work together.',
    description:
        'Control another screen or move this setup without re-entering every '
        'service.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.switch_account_rounded,
    label: 'Profiles',
    subtitle: 'Who can use this device',
    eyebrow: 'Profiles',
    title: 'One device, many viewers.',
    description:
        'Switch between people, add someone new, and shape what each '
        'profile can reach.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.sync_alt_rounded,
    label: 'Sync and Migrate',
    subtitle: 'Sync across devices with WebDAV',
    eyebrow: 'Sync and Migrate',
    title: 'Keep your devices in sync.',
    description:
        'Connect your WebDAV account to sync profiles, settings and watch '
        'progress.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.storage_rounded,
    label: 'Data & Backup',
    subtitle: 'Downloads, backup & restore',
    eyebrow: 'Data & Backup',
    title: 'Your data, under your control.',
    description:
        'Downloads, playback state, and portable backups are separated into '
        'clear actions.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.info_outline_rounded,
    label: 'About',
    subtitle: 'Updates, version & community',
    eyebrow: 'About',
    title: 'Debrify, up to date.',
    description:
        'Version, release checks, and the places where the community meets.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.warning_amber_rounded,
    label: 'Danger Zone',
    subtitle: 'Reset Debrify',
    eyebrow: 'Danger Zone',
    title: 'Start over, deliberately.',
    description:
        'Destructive actions stay isolated and explain exactly what they '
        'remove.',
    destructive: true,
  ),
];
