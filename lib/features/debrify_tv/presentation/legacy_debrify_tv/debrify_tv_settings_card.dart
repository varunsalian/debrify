import 'dart:async';

import 'package:debrify/features/debrify_tv/application/debrify_tv_random_start.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/screens/debrify_tv/widgets/random_start_slider.dart';
import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/debrify_tv_filters.dart';
import 'package:flutter/material.dart';

class DebrifyTvSettingsCard {
  final DebrifyTvDependencies _deps;
  DebrifyTvSettingsCard(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Widget buildSettingsCard({
    required DebrifyTvSettingsScope scope,
    required bool includeNsfwToggle,
    required String title,
    StateSetter? dialogSetState,
  }) {
    final app = AppThemeScope.of(_deps.context());
    final tv = app.debrifyTv;
    final bool isQuickScope = scope == DebrifyTvSettingsScope.quickPlay;

    final bool startRandom = isQuickScope
        ? _owners.settings.quickStartRandom
        : _owners.settings.startRandom;
    void setStartRandom(bool value) {
      _deps.setState(() {
        if (isQuickScope) {
          _owners.settings.quickStartRandom = value;
        } else {
          _owners.settings.startRandom = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvStartRandom(value));
      }
    }

    final int randomStartPercent = isQuickScope
        ? _owners.settings.quickRandomStartPercent
        : _owners.settings.randomStartPercent;
    void setRandomStartPercent(int value) {
      _deps.setState(() {
        if (isQuickScope) {
          _owners.settings.quickRandomStartPercent = value;
        } else {
          _owners.settings.randomStartPercent = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvRandomStartPercent(value));
      }
    }

    final bool showChannelName = isQuickScope
        ? _owners.settings.quickShowChannelName
        : _owners.settings.showChannelName;
    void setShowChannelName(bool value) {
      _deps.setState(() {
        if (isQuickScope) {
          _owners.settings.quickShowChannelName = value;
        } else {
          _owners.settings.showChannelName = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvShowChannelName(value));
      }
    }

    final bool showVideoTitle = isQuickScope
        ? _owners.settings.quickShowVideoTitle
        : _owners.settings.showVideoTitle;
    void setShowVideoTitle(bool value) {
      _deps.setState(() {
        if (isQuickScope) {
          _owners.settings.quickShowVideoTitle = value;
        } else {
          _owners.settings.showVideoTitle = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvShowVideoTitle(value));
      }
    }

    // Hardcoded to false - no longer changeable
    const bool hideOptions = false;
    void setHideOptions(bool value) {
      // No-op: hideOptions is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    // Hardcoded to false - no longer changeable
    const bool hideBackButton = false;
    void setHideBackButton(bool value) {
      // No-op: hideBackButton is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Container(
        decoration: BoxDecoration(
          color: tv.fillWeak.withValues(alpha: .55),
          borderRadius: app.shape.br(20),
          border: Border.all(color: tv.hairline, width: 1),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: tv.textFaint,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Content provider',
              style: Theme.of(
                _deps.context(),
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _sections.chips.providerChoiceChips(
              scope,
              dialogSetState: dialogSetState,
            ),
            const SizedBox(height: 16),
            SwitchRow(
              title: 'Start from random timestamp',
              subtitle: 'Each Debrify TV video starts at a random point',
              value: startRandom,
              onChanged: (v) => setStartRandom(v),
            ),
            if (startRandom) ...[
              const SizedBox(height: 8),
              RandomStartSlider(
                value: randomStartPercent,
                isAndroidTv: _owners.settings.isAndroidTv,
                onChanged: (next) => setRandomStartPercent(next),
                onChangeEnd: isQuickScope
                    ? null
                    : (next) =>
                          DebrifyTvStorage.saveDebrifyTvRandomStartPercent(
                            next,
                          ),
              ),
            ],
            // Removed Hide all options and Hide back button settings
            // These are now hardcoded to false (visible by default)
            if (includeNsfwToggle && isQuickScope) ...[
              const SizedBox(height: 8),
              SwitchRow(
                title: 'Avoid NSFW content',
                subtitle: _owners.settings.viewerForcesNsfw
                    ? 'Always on for this profile'
                    : 'Filter adult/inappropriate torrents • Best effort, not 100% accurate',
                value:
                    _owners.settings.viewerForcesNsfw ||
                    _owners.settings.quickAvoidNsfw,
                onChanged: (v) {
                  // Role-locked: a child session cannot loosen it.
                  if (_owners.settings.viewerForcesNsfw) return;
                  _deps.setState(() {
                    _owners.settings.quickAvoidNsfw = v;
                  });
                  dialogSetState?.call(() {});
                },
              ),
            ],
            const SizedBox(height: 16),
            // Kept LAST (above Reset) on purpose: these are ~14 focusable
            // chips, and placing them higher would push every existing switch
            // that many extra D-pad presses away on TV.
            _sections.chips.tvFilterChips(dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            DebrifyTvDialogButton(
              expand: true,
              icon: Icons.restore_rounded,
              label: 'Reset to defaults',
              onPressed: () async {
                final defaultProvider = _sections.settings
                    .determineDefaultProvider(
                      null,
                      _owners.settings.rdAvailable,
                      _owners.settings.torboxAvailable,
                      _owners.settings.pikpakAvailable,
                      _owners.settings.premiumizeAvailable,
                      _owners.settings.allDebridAvailable,
                    );

                _deps.setState(() {
                  if (isQuickScope) {
                    _owners.settings.quickStartRandom = true;
                    _owners.settings.quickRandomStartPercent =
                        randomStartPercentDefault;
                    _owners.settings.quickHideSeekbar = true;
                    _owners.settings.quickShowChannelName = true;
                    _owners.settings.quickShowVideoTitle = true;
                    _owners.settings.quickHideOptions =
                        false; // Hardcoded to false
                    _owners.settings.quickHideBackButton =
                        false; // Hardcoded to false
                    _owners.settings.quickAvoidNsfw = true;
                    _owners.settings.quickProvider = defaultProvider;
                  } else {
                    _owners.settings.startRandom = true;
                    _owners.settings.randomStartPercent =
                        randomStartPercentDefault;
                    _owners.settings.hideSeekbar = true;
                    _owners.settings.showChannelName = true;
                    _owners.settings.showVideoTitle = true;
                    _owners.settings.hideOptions = false; // Hardcoded to false
                    _owners.settings.hideBackButton =
                        false; // Hardcoded to false
                    _owners.settings.provider = defaultProvider;
                  }
                  // Playback filters are shared by both scopes, so reset
                  // them from either one.
                  _owners.settings.tvFilters = const DebrifyTvFilters.empty();
                });
                _sections.stage.invalidateSpotlightStats();
                dialogSetState?.call(() {});

                await DebrifyTvStorage.setDebrifyTvFilterQualities(const []);
                await DebrifyTvStorage.setDebrifyTvFilterSizes(const []);

                if (!isQuickScope) {
                  await DebrifyTvStorage.saveDebrifyTvStartRandom(true);
                  await DebrifyTvStorage.saveDebrifyTvHideSeekbar(true);
                  await DebrifyTvStorage.saveDebrifyTvShowChannelName(true);
                  await DebrifyTvStorage.saveDebrifyTvShowVideoTitle(true);
                  // No longer saving hideOptions and hideBackButton - they're hardcoded to false
                  await DebrifyTvStorage.saveDebrifyTvProvider(defaultProvider);
                }

                if (!_deps.mounted()) {
                  return;
                }

                ScaffoldMessenger.of(_deps.context()).showSnackBar(
                  const SnackBar(
                    content: Text('Reset to defaults successful'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
