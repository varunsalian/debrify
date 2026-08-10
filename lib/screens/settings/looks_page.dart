import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../theme/app_looks.dart';
import '../../theme/app_theme_controller.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import 'theme_tokens_page.dart';
import 'widgets/settings_widgets.dart';

/// Appearance → **Looks**.
///
/// One pick that sets a curated bundle, placed above the individual pickers
/// because it is the entry point they are alternatives to. Nothing is removed:
/// every one of the fourteen style pickers is still exactly where it was, and
/// touching one afterwards simply moves this page to *Custom*.
class LooksPage extends StatefulWidget {
  const LooksPage({super.key});

  @override
  State<LooksPage> createState() => _LooksPageState();
}

class _LooksPageState extends State<LooksPage> {
  /// Non-focusable marker around the options card; on TV it hands entry focus
  /// to the first option row. Same idiom as the other Appearance pickers.
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'looks-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  bool _applying = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('looks_settings');
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

  Future<void> _apply(AppLook look) async {
    if (_applying) return;
    setState(() => _applying = true);
    // Cleared BEFORE the apply, not after.
    //
    // A Look is a complete statement about how the app looks, so edits layered
    // under one have to go — but `apply` is an asynchronous multi-key write,
    // and a trailing clear would also delete an edit the user made WHILE it was
    // running. Clearing first means later intent simply wins, which is the same
    // rule `LookApplier`'s own generation protocol follows.
    await AppThemeController.instance.clearOverrides();
    await LookApplier.apply(look);
    if (!mounted) return;
    // Nothing to store: `AppLooks.active()` recomputes from the prefs
    // themselves, so this rebuild is the whole "selection" mechanism.
    setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final edits = AppThemeController.instance.overrides.count;
    // A Look with tokens edited on top is NOT that Look, and `AppLooks.active`
    // cannot know — it compares the keys a Look names, and overrides are not
    // one of them. Showing a tick next to a Look the app no longer looks like
    // is a lie the user has no way to detect.
    final active = edits == 0 ? AppLooks.active() : null;
    return SettingsPageScaffold(
      title: 'Looks',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Looks',
                  subtitle: 'One pick that dresses the whole app',
                ),
                const SizedBox(height: 18),
                if (active == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SettingsInfoBanner(
                      icon: Icons.tune_rounded,
                      text: edits > 0
                          ? 'Custom — $edits '
                              '${edits == 1 ? "token" : "tokens"} edited under '
                              'Advanced. Picking a Look below clears them.'
                          : 'Custom — your settings don\'t match a Look. '
                              'Picking one below replaces them; everything '
                              'stays editable afterwards.',
                    ),
                  ),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final look in AppLooks.all)
                        SettingsTile(
                          icon: look.id == active?.id
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          title: look.label,
                          // A Look with edits on top is NOT the Look, and
                          // saying it is would be a lie by omission — the key
                          // set matches, so `isActive` alone cannot tell.
                          subtitle: look.blurb,
                          trailing: look.id == active?.id
                              ? Icon(Icons.check_rounded,
                                  size: 20, color: app.settings.accent2)
                              : const SizedBox.shrink(),
                          onTap: () => _apply(look),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SettingsSection(
                  title: '',
                  children: [
                    SettingsTile(
                      icon: Icons.tune_rounded,
                      title: 'Advanced',
                      subtitle: edits == 0
                          ? 'Edit individual tokens — colour, shape, motion'
                          : '$edits ${edits == 1 ? "token" : "tokens"} '
                              'changed over this Look',
                      onTap: () async {
                        await pushSettingsPage(
                          context,
                          const ThemeTokensPage(),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'A Look sets the app theme, the details page, the launch '
                  'ident and the TV layouts together, so they agree with each '
                  'other. It only touches what it names — anything else you '
                  'have set is left alone, and every individual picker is '
                  'still below.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: app.settings.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
