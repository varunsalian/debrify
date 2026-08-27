import 'package:flutter/material.dart';

import '../profiles/profile_wall_screen.dart';
import '../../services/analytics_service.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/tvos_top_shelf_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

/// Appearance → Profile picker.
///
/// Device-level presentation lives here rather than in the household hub:
/// the picker style exists before any profile is selected, and Apple TV's Top
/// Shelf is shell chrome rather than an action on a person.
class ProfileAppearancePage extends StatefulWidget {
  const ProfileAppearancePage({super.key});

  @override
  State<ProfileAppearancePage> createState() => _ProfileAppearancePageState();
}

class _ProfileAppearancePageState extends State<ProfileAppearancePage> {
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'profile-appearance-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  bool _loading = true;
  String _style = ProfileGateStyle.cached;
  bool _topShelfEnabled = false;
  bool _mayManageTopShelf = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('profile_appearance_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await ProfileGateStyle.warm();
    var mayManageTopShelf = false;
    var topShelf = false;
    if (PlatformUtil.isTvOS) {
      try {
        final registry = ProfileBootstrap.registry;
        final authorization = await ProfileAuthorizationContext.capture(
          registry,
        );
        final actor = await authorization.validate(registry);
        mayManageTopShelf =
            TvosTopShelfService.canManageMultiProfilePersonalization(actor);
        if (mayManageTopShelf) {
          topShelf = await TvosTopShelfService.instance
              .multiProfilePersonalizationEnabled();
        }
      } catch (_) {
        // Legacy mode, a stale session, or failed authorization must not
        // expose a control whose service boundary will reject the write.
        mayManageTopShelf = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _style = ProfileGateStyle.cached;
      _topShelfEnabled = topShelf;
      _mayManageTopShelf = mayManageTopShelf;
      _loading = false;
    });
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  Future<void> _selectStyle(String style) async {
    if (style == _style) return;
    setState(() => _style = style);
    await ProfileGateStyle.set(style);
  }

  Future<void> _setTopShelf(bool enabled) async {
    try {
      await TvosTopShelfService.instance.setMultiProfilePersonalizationEnabled(
        enabled,
      );
      if (mounted) setState(() => _topShelfEnabled = enabled);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Top Shelf setting could not be changed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Profile Appearance',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kSettingsMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SettingsPageHeader(
                        icon: Icons.switch_account_rounded,
                        title: 'Profile picker',
                        subtitle:
                            'How Debrify welcomes everyone on this device',
                      ),
                      const SizedBox(height: 24),
                      Focus(
                        focusNode: _firstCardMarker,
                        canRequestFocus: false,
                        skipTraversal: true,
                        child: SettingsSection(
                          title: 'Layout',
                          children: [
                            for (final option in ProfileGateStyle.options)
                              SettingsTile(
                                icon: option.id == _style
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                title: option.label,
                                subtitle:
                                    option.id == ProfileGateStyle.defaultStyle
                                    ? '${option.blurb} · default'
                                    : option.blurb,
                                trailing: option.id == _style
                                    ? const Icon(Icons.check_rounded)
                                    : const SizedBox.shrink(),
                                onTap: () => _selectStyle(option.id),
                              ),
                          ],
                        ),
                      ),
                      if (PlatformUtil.isTvOS && _mayManageTopShelf) ...[
                        const SizedBox(height: 18),
                        SettingsSection(
                          title: 'Apple TV',
                          children: [
                            SettingsToggleTile(
                              icon: Icons.tv_rounded,
                              title: 'Personalized Top Shelf',
                              subtitle:
                                  'Show the unlocked active profile on the Apple TV Home Screen',
                              value: _topShelfEnabled,
                              onChanged: _setTopShelf,
                              subtitleMaxLines: 2,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
