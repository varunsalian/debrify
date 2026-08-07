import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

/// Android TV "Rendering" picker — whether the UI is drawn at the panel's own
/// resolution or at a ~720p buffer the TV's scaler blows back up.
///
/// TVs are fill-rate bound in a way phones aren't: on GLES2-class boxes the
/// same build at 720p feels near native where 1080p judders, no matter how
/// lean the widget tree is. MainActivity has always made that call
/// automatically from the reported GLES version — but that's a coarse proxy
/// for throughput, so mid-tier hardware that reports GLES 3.x while performing
/// like GLES 2.0 lands on the full-resolution branch with no way off it. This
/// page is the way off it.
///
/// Automatic is not "off": the pref's ABSENCE is what keeps the device
/// decision alive, which is why [StorageService.setTvRenderQuality] removes
/// the key rather than writing `false`.
///
/// Its own page rather than rows inline in the Appearance pane so the setting
/// is reachable from Settings search like every other destination — people
/// hunting this will search "stutter" or "lag", not "rendering".
class TvRenderQualityPage extends StatefulWidget {
  const TvRenderQualityPage({super.key});

  @override
  State<TvRenderQualityPage> createState() => _TvRenderQualityPageState();
}

class _TvRenderQualityPageState extends State<TvRenderQualityPage> {
  bool _loading = true;
  TvRenderQuality _quality = TvRenderQuality.auto;

  /// What the RUNNING engine actually landed on, straight from MainActivity.
  /// Null only where MainActivity never ran (iOS/desktop) — every Android
  /// launch writes it, so this page's TV-only audience always has a value.
  bool? _activeLowRes;

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'tv-render-quality-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('tv_render_quality_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final quality = await StorageService.getTvRenderQuality();
    final active = await StorageService.getTvLowResRenderActive();
    if (!mounted) return;
    setState(() {
      _quality = quality;
      _activeLowRes = active;
      _loading = false;
    });
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Don't yank focus if it already landed on a real node (only the
        // route's FocusScope holds focus while nothing is focused yet).
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  Future<void> _select(TvRenderQuality quality) async {
    if (quality == _quality) return;
    setState(() => _quality = quality);
    await StorageService.setTvRenderQuality(quality);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rendering saved — restart Debrify to apply it.'),
      ),
    );
  }

  /// One line of ground truth under the options: the pref says what WILL
  /// happen, this says what the engine on screen is doing right now. Under
  /// Automatic it's the only way to see which branch this TV was put on, and
  /// after a change it's what makes "restart to apply" believable rather than
  /// something the user has to take on faith.
  String get _currentlyLine {
    final active = _activeLowRes;
    if (active == null) return '';
    return active
        ? 'Right now: drawing at about 720p.'
        : "Right now: drawing at the panel's full resolution.";
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Rendering',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currently = _currentlyLine;

    return SettingsPageScaffold(
      title: 'Rendering',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.hd_rounded,
                  title: 'Rendering',
                  subtitle: 'Trade sharpness for smoother navigation',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kTvRenderQualityChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'TVs have far weaker graphics than phones, and drawing the '
                  'whole interface at 4K or 1080p is what makes some of them '
                  'feel heavy. Drawing at 720p and letting the TV scale the '
                  'picture up costs a lot less per frame, so menus and rows '
                  'move more smoothly — at the price of softer text and art. '
                  'Debrify normally picks for you; change this if scrolling '
                  'stutters, or if the picture looks softer than it should. '
                  'Takes effect the next time Debrify starts.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: kSettingsDim,
                  ),
                ),
                if (currently.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    currently,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: kSettingsAccent2,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'On TVs with weaker graphics, "Sharper picture" also turns '
                  'off the ambient trailers that play behind the home screen '
                  'and detail pages — at full resolution there is no headroom '
                  'left to blend video under the interface.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: kSettingsDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Radio-style row — a plain [SettingsTile] (the DPAD-proven row) with a
  /// check on the active one, rather than a dropdown whose overlay would have
  /// to be focus-managed on a remote.
  Widget _optionRow(TvRenderQualityChoice choice) {
    final bool active = _quality == choice.quality;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? const Icon(Icons.check_rounded, size: 20, color: kSettingsAccent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.quality),
    );
  }
}
