import 'package:flutter/material.dart';

import '../../services/tv_motion_profile.dart';
import '../../theme/app_theme_scope.dart';
import 'widgets/settings_widgets.dart';

/// Uses the existing settings radio-row and DPAD navigation conventions.
class TvMotionPage extends StatefulWidget {
  const TvMotionPage({super.key});

  @override
  State<TvMotionPage> createState() => _TvMotionPageState();
}

class _TvMotionPageState extends State<TvMotionPage> {
  final _nodes = [for (final _ in TvMotionProfile.values) FocusNode()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[TvMotionController.current.index].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'TV motion',
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsPageHeader(
                icon: Icons.slow_motion_video_rounded,
                title: 'TV motion',
                subtitle:
                    'Scrolling on Spotlight Home. Saved for this profile '
                    'on this device; other Home layouts keep their current motion.',
              ),
              const SizedBox(height: 24),
              ValueListenableBuilder<TvMotionProfile>(
                valueListenable: TvMotionController.notifier,
                builder: (context, selected, _) => SettingsSection(
                  title: '',
                  children: [
                    for (final profile in TvMotionProfile.values)
                      SettingsTile(
                        icon: selected == profile
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        title: profile.label,
                        subtitle: profile.description,
                        focusNode: _nodes[profile.index],
                        trailing: selected == profile
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: AppThemeScope.of(
                                  context,
                                ).settings.accent2,
                              )
                            : const SizedBox.shrink(),
                        onTap: () => TvMotionController.select(profile),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
