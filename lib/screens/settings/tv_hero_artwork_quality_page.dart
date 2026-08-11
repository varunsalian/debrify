import 'package:flutter/material.dart';

import '../../models/tv_hero_artwork_quality.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/tv_hero_artwork_quality_controller.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

class TvHeroArtworkQualityChoice {
  const TvHeroArtworkQualityChoice(this.quality, this.label, this.subtitle);

  final TvHeroArtworkQuality quality;
  final String label;
  final String subtitle;
}

const List<TvHeroArtworkQualityChoice> kTvHeroArtworkQualityChoices = [
  TvHeroArtworkQualityChoice(
    TvHeroArtworkQuality.automatic,
    'Automatic',
    'Full HD on capable TVs; lighter artwork in low-resolution TV mode',
  ),
  TvHeroArtworkQualityChoice(
    TvHeroArtworkQuality.performance,
    'Performance',
    'Decode landscape hero artwork around 1080×608',
  ),
  TvHeroArtworkQualityChoice(
    TvHeroArtworkQuality.fullHd,
    'Full HD',
    'Preserve artwork up to 1920×1080 for the sharpest hero',
  ),
];

String tvHeroArtworkQualityLabel(TvHeroArtworkQuality quality) {
  for (final choice in kTvHeroArtworkQualityChoices) {
    if (choice.quality == quality) return choice.label;
  }
  return 'Automatic';
}

/// TV-only artwork decode picker shared by Android TV and tvOS.
class TvHeroArtworkQualityPage extends StatefulWidget {
  const TvHeroArtworkQualityPage({super.key});

  @override
  State<TvHeroArtworkQualityPage> createState() =>
      _TvHeroArtworkQualityPageState();
}

class _TvHeroArtworkQualityPageState extends State<TvHeroArtworkQualityPage> {
  TvHeroArtworkQuality _quality = TvHeroArtworkQualityController.quality;

  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'tv-hero-artwork-quality-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('tv_hero_artwork_quality_settings');
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _select(TvHeroArtworkQuality quality) async {
    if (quality == _quality) return;
    setState(() => _quality = quality);
    await TvHeroArtworkQualityController.setQuality(quality);
    MainPageBridge.tvHeroArtworkQualityChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return SettingsPageScaffold(
      title: 'Hero Artwork Quality',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.photo_size_select_large_rounded,
                  title: 'Hero Artwork Quality',
                  subtitle:
                      'Balance sharper Home artwork against TV memory use',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kTvHeroArtworkQualityChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'The source image is unchanged. This controls the maximum '
                  'size Debrify decodes into memory for Home hero and stage '
                  'artwork. Portrait poster fallbacks are also height-bounded '
                  'to avoid oversized textures. Changes apply immediately.',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: t.dim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionRow(TvHeroArtworkQualityChoice choice) {
    final t = AppThemeScope.of(context).settings;
    final active = _quality == choice.quality;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.quality),
    );
  }
}
