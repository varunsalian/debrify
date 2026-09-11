import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../utils/platform_util.dart';
import 'external_player_settings_page.dart';
import 'playback_settings_section.dart';
import 'widgets/settings_widgets.dart';

/// Settings → Playback remains the single entry point on every device.
class PlaybackSettingsPage extends StatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  State<PlaybackSettingsPage> createState() => _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends State<PlaybackSettingsPage> {
  final _firstRow = FocusNode(debugLabel: 'playback-player-category');

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('playback_settings');
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary == null || primary is FocusScopeNode) {
          _firstRow.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _firstRow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Playback',
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsPageHeader(
                icon: Icons.play_circle_outline_rounded,
                title: 'Playback',
                subtitle: 'Player, video, audio and subtitles',
              ),
              const SizedBox(height: 24),
              SettingsSection(
                title: '',
                children: [
                  for (final section in PlaybackSettingsSection.values)
                    SettingsTile(
                      key: ValueKey('playback-category-${section.name}'),
                      icon: section.icon,
                      title: section.label,
                      subtitle: section.description,
                      focusNode: section == PlaybackSettingsSection.player
                          ? _firstRow
                          : null,
                      onTap: () async {
                        await pushSettingsPage(
                          context,
                          ExternalPlayerSettingsPage(section: section),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
