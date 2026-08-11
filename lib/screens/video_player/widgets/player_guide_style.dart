import 'package:flutter/material.dart';

import '../../../widgets/iptv/styles/iptv_style.dart';

/// The in-player IPTV guide look, chosen in IPTV settings and persisted as
/// the `iptv_player_guide_style` preference
/// (see `StorageService.getIptvPlayerGuideStyle`). Read once at player
/// launch — changing it applies to the next playback session.
///
/// `classic` is the shipped look and takes the UNTOUCHED legacy build paths
/// everywhere — widgets branch on the style FIRST and only the styled
/// branches read tokens, which is what keeps the default provably
/// pixel-identical to today. Both players implement the same four styles:
/// this enum for the Dart player, `GuideStyle` in
/// `AndroidTvTorrentPlayerActivity.kt` for the native TV player.
///
/// Independent of the IPTV page's `iptv_style` pref: the page restyles the
/// cockpit, this restyles the surfaces that float over playing video.
enum PlayerGuideStyle {
  classic,
  glass,
  edition,
  console,
  spotlight;

  static PlayerGuideStyle fromPref(String raw) => switch (raw) {
    'glass' => PlayerGuideStyle.glass,
    'edition' => PlayerGuideStyle.edition,
    'console' => PlayerGuideStyle.console,
    'spotlight' => PlayerGuideStyle.spotlight,
    _ => PlayerGuideStyle.classic,
  };

  String get prefValue => name;

  bool get isStyled => this != PlayerGuideStyle.classic;
}

/// Player presets of the page's token type. The page presets are opaque
/// slabs; these surfaces float over live video, so the panel/bg tones carry
/// pre-multiplied translucency instead (house rule: no `Opacity` widgets
/// over video — bake the alpha into the color).
abstract final class PlayerGuideTokens {
  /// Cinema Glass — deep translucent panels, one restrained violet accent,
  /// app default type. The "clean modern streaming" one.
  static const IptvStyleTokens glass = IptvStyleTokens(
    bg: Color(0xFF0A0C12),
    panel: Color(0xF20E1118),
    fg: Color(0xFFF2F5FA),
    fgMid: Color(0xCCF2F5FA), // 80%
    fgDim: Color(0x8CF2F5FA), // 55%
    fgFaint: Color(0x54F2F5FA), // 33%
    hairline: Color(0x16FFFFFF), // 9%
    hairline2: Color(0x2BFFFFFF), // 17%
    accent: Color(0xFF8F7BFF), // restrained violet — the ONLY color
    rec: Color(0xFFFF4545),
    live: Color(0xFF34D399),
    selectedTint: Color(0x148F7BFF), // 8% violet
    focusTint: Color(0x0F8F7BFF), // 6% violet
  );

  /// Midnight Edition — First Edition's ink/cream/serif grammar adapted for
  /// over-video use (the page's paper panels would blind a dark room).
  static const IptvStyleTokens edition = IptvStyleTokens(
    bg: Color(0xF00D0B09),
    panel: Color(0xF2141110),
    fg: Color(0xFFF3EEE3),
    fgMid: Color(0xCCF3EEE3), // 80%
    fgDim: Color(0x8CF3EEE3), // 55%
    fgFaint: Color(0x59F3EEE3), // 35%
    hairline: Color(0x17F3EEE3), // 9%
    hairline2: Color(0x29F3EEE3), // 16%
    accent: Color(0xFFF3EEE3), // paper — edition has no color accent
    rec: Color(0xFFE5484D),
    live: Color(0xFFB8C79B),
    selectedTint: Color(0x0DF3EEE3), // 5%
    focusTint: Color(0x09F3EEE3), // 3.5%
    headlineFamily: 'Fraunces72',
    captionFamily: 'Fraunces9',
  );

  /// Master Control — black instrument, amber time machinery, mono readouts.
  static const IptvStyleTokens console = IptvStyleTokens(
    bg: Color(0xF2050505),
    panel: Color(0xF50A0A0A),
    fg: Color(0xFFEDEDED),
    fgMid: Color(0xB3EDEDED), // 70%
    fgDim: Color(0x73EDEDED), // 45%
    fgFaint: Color(0x47EDEDED), // 28%
    hairline: Color(0x14FFFFFF), // 8%
    hairline2: Color(0x26FFFFFF), // 15%
    accent: Color(0xFFF2A93B), // amber — time/focus machinery ONLY
    rec: Color(0xFFFF4545),
    live: Color(0xFF34D399),
    selectedTint: Color(0x0FF2A93B), // 6% amber
    focusTint: Color(0x0DF2A93B), // 5% amber
    nameFamily: 'SpaceGrotesk',
    monoFamily: 'JetBrainsMono',
  );

  /// Spotlight — the tvOS idiom: black glass, white ink, no chrome color,
  /// and the white-pill inverse focus ([IptvStyleTokens.focusFill]).
  /// Crimson is a status color only (rec/live).
  static const IptvStyleTokens spotlight = IptvStyleTokens(
    bg: Color(0x8C101012), // 55% glass — the video stays present behind
    panel: Color(0xF2101012),
    fg: Color(0xFFFFFFFF),
    fgMid: Color(0xCCFFFFFF), // 80%
    fgDim: Color(0x8CFFFFFF), // 55%
    fgFaint: Color(0x54FFFFFF), // 33%
    hairline: Color(0x24FFFFFF), // 14%
    hairline2: Color(0x3DFFFFFF), // 24%
    accent: Color(0xFFFFFFFF), // white — spotlight has no chrome color
    rec: Color(0xFFE23D4C),
    live: Color(0xFFE23D4C),
    selectedTint: Color(0x1AFFFFFF), // 10%
    focusTint: Color(0x14FFFFFF), // 8% (fallback where fill isn't used)
    focusFill: Color(0xFFFFFFFF),
    focusInk: Color(0xFF000000),
  );

  static IptvStyleTokens? of(PlayerGuideStyle style) => switch (style) {
    PlayerGuideStyle.classic => null,
    PlayerGuideStyle.glass => glass,
    PlayerGuideStyle.edition => edition,
    PlayerGuideStyle.console => console,
    PlayerGuideStyle.spotlight => spotlight,
  };
}
