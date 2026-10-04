import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

typedef PlaybackIosSectionDependencies = ({
  Widget Function(iOSExternalPlayer player) buildIOSPlayerTile,
  Future<void> Function() clearIOSCustomScheme,
  BuildContext Function() context,
  PlaybackCoreState core,
  PlaybackIosState ios,
  Future<void> Function() saveIOSCustomScheme,
  void Function(VoidCallback) setState,
});

class PlaybackIosSection {
  final PlaybackIosSectionDependencies _deps;
  PlaybackIosSection(this._deps);
  List<Widget> iosSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      // iOS + Apple TV player selection (same catalog; tvOS shows
      // only the players that ship an Apple TV app)
      if ((PlatformUtil.isIosMobile || PlatformUtil.isTvOS) &&
          _deps.core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Preferred Player',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select the app to open videos with. Make sure the app is installed from the App Store.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
              ),
              const SizedBox(height: 8),
              // tvOS lists only players with a real Apple TV app —
              // a row that can never launch is worse than no row.
              ...[
                for (final (i, player)
                    in iOSExternalPlayer.values
                        .where((p) => !PlatformUtil.isTvOS || p.availableOnTvos)
                        .indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _deps.buildIOSPlayerTile(player),
                ],
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // iOS Custom URL Scheme configuration
      if ((PlatformUtil.isIosMobile || PlatformUtil.isTvOS) &&
          _deps.core.defaultPlayerMode == 'external' &&
          _deps.ios.selectedIOSPlayer == iOSExternalPlayer.customScheme) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom URL Scheme',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Define a custom URL scheme to launch videos',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _deps.ios.iosSchemeFocused
                        ? [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: TvTextField(
                    controller: _deps.ios.iosSchemeController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _deps.ios.iosSchemeFocusNode,
                    decoration: InputDecoration(
                      labelText: 'URL Scheme Template',
                      hintText: 'myplayer://play?url={url}',
                      helperText: 'Use {url} for the video URL',
                      helperMaxLines: 2,
                      errorText: _deps.ios.iosSchemeError,
                      prefixIcon: const Icon(Icons.link_rounded),
                    ),
                    onChanged: (_) {
                      if (_deps.ios.iosSchemeError != null) {
                        _deps.setState(() {
                          _deps.ios.iosSchemeError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _deps.saveIOSCustomScheme,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                    if (_deps.ios.iosCustomScheme != null &&
                        _deps.ios.iosCustomScheme!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _deps.clearIOSCustomScheme,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examples',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'vlc://{url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'infuse://x-callback-url/play?url={url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'customapp://stream?video={url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],

      // iOS external player info
      if ((PlatformUtil.isIosMobile || PlatformUtil.isTvOS) &&
          _deps.core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Videos will open in the selected app using URL schemes. Make sure the player app is installed from the App Store.',
        ),
      ],
    ];
  }
}
