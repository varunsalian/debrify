import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/screens/settings/app_theme_page.dart';
import 'package:debrify/screens/settings/debrify_tv_player_style_page.dart';
import 'package:debrify/screens/settings/debrify_tv_style_page.dart';
import 'package:debrify/screens/settings/desktop_sidebar_style_page.dart';
import 'package:debrify/screens/settings/detail_page_style_page.dart';
import 'package:debrify/screens/settings/detail_theme_page.dart';
import 'package:debrify/screens/settings/discover_layout_page.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart';
import 'package:debrify/screens/settings/launch_animation_page.dart';
import 'package:debrify/screens/settings/looks_page.dart';
import 'package:debrify/screens/settings/parents_guide_style_page.dart';
import 'package:debrify/screens/settings/play_loader_style_page.dart';
import 'package:debrify/screens/settings/player_dock_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/profile_appearance_page.dart';
import 'package:debrify/screens/settings/sidebar_customization_page.dart';
import 'package:debrify/screens/settings/text_brightness_page.dart';
import 'package:debrify/screens/settings/theme_lab_page.dart';
import 'package:debrify/screens/settings/theme_tokens_page.dart';
import 'package:debrify/screens/settings/tv_collection_list_style_page.dart';
import 'package:debrify/screens/settings/tv_hero_artwork_quality_page.dart';
import 'package:debrify/screens/settings/tv_home_style_page.dart';
import 'package:debrify/screens/settings/tv_player_controls_style_page.dart';
import 'package:debrify/screens/settings/tv_render_quality_page.dart';
import 'package:debrify/screens/settings/tv_screen_size_page.dart';
import 'package:debrify/screens/settings/tv_sidebar_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/discover_storage.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/launch_ident_storage.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/services/storage/sidebar_storage.dart';
import 'package:debrify/services/storage/theme_storage.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:flutter/material.dart';
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsAppearanceNavigation {
  SettingsAppearanceNavigation(this._summaries, this._deps);
  final ({
    BuildContext Function() context,
    bool Function() mounted,
    StateSetter setState,
  })
  _deps;
  final SettingsSummaries _summaries;

  Future<void> toggleTvKeyboard(bool enabled) async {
    _deps.setState(() {
      _summaries.tvKeyboardEnabled = enabled;
    });
    await TvDisplayStorage.setTvKeyboardEnabled(enabled);
  }

  /// The page writes the pref itself (and says a restart is needed — the
  /// engine is built with the factor in MainActivity.onCreate); re-read it on
  /// the way back so the rail row's caption matches.
  Future<void> openTvScreenSize() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TvScreenSizePage());
    if (!context.mounted) return;
    final percent = await TvDisplayStorage.getTvUiScalePercent();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.tvUiScalePercent = percent;
    });
  }

  /// Same contract as [openTvScreenSize] — MainActivity reads the render
  /// pref in `onCreate` too, so the page owns the write and the restart
  /// notice; we only re-read for the row's caption.
  Future<void> openTvRenderQuality() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TvRenderQualityPage());
    if (!context.mounted) return;
    final quality = await TvDisplayStorage.getTvRenderQuality();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.tvRenderQuality = quality;
    });
  }

  Future<void> openTvHeroArtworkQuality() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TvHeroArtworkQualityPage());
    if (!context.mounted) return;
    final quality = await TvDisplayStorage.getTvHeroArtworkQuality();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.tvHeroArtworkQuality = quality;
    });
  }

  /// The page writes the pref and live-applies via MainPageBridge; re-read it
  /// on the way back so the rail row's caption matches.
  Future<void> openTvHomeStyle() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TvHomeStylePage());
    if (!context.mounted) return;
    final style = await HomeAppearanceStorage.getTvHomeStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.tvHomeStyle = style;
    });
  }

  /// Same contract as [openTvHomeStyle], for the Discover layout picker.
  Future<void> openCollectionListStyle() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TvCollectionListStylePage());
  }

  Future<void> openDiscoverLayout() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DiscoverLayoutPage());
    if (!context.mounted) return;
    final layout = await DiscoverStorage.getDiscoverLayout();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.discoverLayout = layout;
    });
  }

  /// Same contract as [openTvHomeStyle], for the sidebar chrome picker.
  Future<void> openTvSidebarStyle() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TvSidebarStylePage());
    if (!context.mounted) return;
    final style = await SidebarStorage.getTvSidebarStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.tvSidebarStyle = style;
    });
  }

  /// Same contract, for the desktop/tablet sidebar picker.
  Future<void> openDesktopSidebarStyle() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DesktopSidebarStylePage());
    if (!context.mounted) return;
    final style = await SidebarStorage.getDesktopSidebarStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.desktopSidebarStyle = style;
    });
  }

  Future<void> openSidebarCustomization() async {
    final context = _deps.context();
    await pushSettingsPage(context, const SidebarCustomizationPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openProfileAppearance() async {
    final context = _deps.context();
    await pushSettingsPage(context, const ProfileAppearancePage());
    if (!context.mounted) return;
    await ProfileGateStyle.warm();
    if (context.mounted) _deps.setState(() {});
  }

  /// Same contract as [openTvHomeStyle], for the IPTV page look picker.
  Future<void> openIptvStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const IptvStylePage());
    if (!context.mounted) return;
    final style = await IptvAppearanceStorage.getIptvStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.iptvStyle = style;
    });
  }

  Future<void> openDebrifyTvStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DebrifyTvStylePage());
    if (!context.mounted) return;
    final style = await DebrifyTvStorage.getDebrifyTvStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.debrifyTvStyle = style;
    });
  }

  /// Same contract as [openTvHomeStyle], for the in-player guide picker.
  Future<void> openPlayerGuideStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const PlayerGuideStylePage());
    if (!context.mounted) return;
    final style = await IptvAppearanceStorage.getIptvPlayerGuideStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.playerGuideStyle = style;
    });
  }

  /// Same contract as [openTvHomeStyle], for the play loader look. Also
  /// re-warms the synchronous mirror the play path reads, so a change picked
  /// here applies to the very next play.
  Future<void> openPlayLoaderStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const PlayLoaderStylePage());
    if (!context.mounted) return;
    await PlayLoaderStyleController.warm();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.playLoaderStyle = PlayLoaderStyleController.cached;
    });
  }

  /// Same contract as [openTvHomeStyle], for the native TV control skin.
  Future<void> openTvPlayerControlsStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TvPlayerControlsStylePage());
    if (!context.mounted) return;
    final style = await PlayerAppearanceStorage.getTvPlayerControlsStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.tvPlayerControlsStyle = style;
    });
  }

  /// Same contract as [openTvHomeStyle], for the Debrify TV playback screen.
  Future<void> openDebrifyTvPlayerStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DebrifyTvPlayerStylePage());
    if (!context.mounted) return;
    final style = await DebrifyTvStorage.getDebrifyTvPlayerStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.debrifyTvPlayerStyle = style;
    });
  }

  /// Same contract as [openTvHomeStyle], for the player control dock.
  Future<void> openPlayerDockPage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const PlayerDockPage());
    if (!context.mounted) return;
    final style = await PlayerAppearanceStorage.getPlayerDockStyle();
    final palette = await PlayerAppearanceStorage.getPlayerDockPalette();
    final size = await PlayerAppearanceStorage.getPlayerDockSize();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.playerDockStyle = style;
      _summaries.playerDockPalette = palette;
      _summaries.playerDockSize = size;
    });
  }

  /// Same contract as [openTvHomeStyle], for the details-page layout picker.
  Future<void> openDetailPageStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DetailPageStylePage());
    if (!context.mounted) return;
    final style = await DetailPageStorage.getDetailPageStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.detailPageStyle = style;
    });
  }

  /// Same contract as [openTvHomeStyle], for the details-page theme picker.
  Future<void> openDetailThemePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const DetailThemePage());
    if (!context.mounted) return;
    final theme = await DetailPageStorage.getDetailTheme();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.detailTheme = theme;
    });
  }

  /// Appearance → Theme Lab. The setState on return covers the feedback
  /// toggles the lab hosts — their values are read from the synchronous
  /// mirrors, so one rebuild is the whole refresh.
  Future<void> openThemeLab() async {
    final context = _deps.context();
    await pushSettingsPage(context, const ThemeLabPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  /// Appearance → Looks. Re-reads nothing on return: the row's subtitle is
  /// COMPUTED from the live prefs (`AppLooks.active()`), so one setState is
  /// the whole refresh — there is no stored "current Look" that could drift.
  Future<void> openLooksPage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const LooksPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  Future<void> openThemeTokensPage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const ThemeTokensPage());
    if (!context.mounted) return;
    _deps.setState(() {});
  }

  /// How many tokens have been taken over, or the invitation when none have.
  ///
  /// Computed from the live overrides rather than stored, for the same reason
  /// `AppLooks.active()` is: there is nothing to keep in sync and no way for a
  /// remembered answer to go stale.
  String get themeTokensLabel {
    final n = AppThemeController.instance.overrides.count;
    if (n == 0) return 'Colour, shape, motion — one token at a time';
    return '$n ${n == 1 ? "token" : "tokens"} changed';
  }

  Future<void> openAppThemePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const AppThemePage());
    if (!context.mounted) return;
    final theme = await DetailPageStorage.getDetailTheme();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.detailTheme = theme;
    });
  }

  Future<void> openParentsGuideStylePage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const ParentsGuideStylePage());
    if (!context.mounted) return;
    final style = await DetailPageStorage.getParentsGuideStyle();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.parentsGuideStyle = style;
    });
  }

  /// Same contract as [openTvHomeStyle], for the text brightness picker.
  Future<void> openTextBrightnessPage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const TextBrightnessPage());
    if (!context.mounted) return;
    final value = await ThemeStorage.getTextBrightness();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.textBrightness = value;
    });
  }

  /// Same contract as [openTvHomeStyle], for the launch ident picker.
  Future<void> openLaunchAnimationPage() async {
    final context = _deps.context();
    await pushSettingsPage(context, const LaunchAnimationPage());
    if (!context.mounted) return;
    final value = await LaunchIdentStorage.getLaunchAnimation();
    if (!context.mounted) return;
    _deps.setState(() {
      _summaries.launchAnimation = value;
    });
  }
}
