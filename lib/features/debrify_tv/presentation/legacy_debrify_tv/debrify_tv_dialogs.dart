import 'dart:async';

import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

class DebrifyTvDialogs {
  final DebrifyTvDependencies _deps;
  DebrifyTvDialogs(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  // TV Channel Options Menu (Edit/Delete)
  Future<void> showTvChannelOptionsMenu(DebrifyTvChannel channel) async {
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);

    await showDialog<void>(
      context: _deps.context(),
      builder: (dialogContext) {
        return DebrifyTvSpotlightDialog(
          eyebrow:
              'Channel actions · ${channel.channelNumber.toString().padLeft(2, '0')}',
          title: channel.name,
          subtitle: 'Manage this channel without leaving the current view.',
          icon: Icons.tune_rounded,
          maxWidth: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DebrifyTvDialogOptionCard(
                autofocus: true,
                icon: isFavorited
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                title: isFavorited ? 'Remove pin' : 'Pin channel',
                subtitle: isFavorited
                    ? 'Return this channel to the main list.'
                    : 'Keep this channel at the top of the rail.',
                tag: isFavorited ? 'Pinned' : 'Pin',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.library.toggleChannelFavorite(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.edit_rounded,
                title: 'Edit channel',
                subtitle: 'Change its name, keywords, or content filter.',
                tag: 'Edit',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.actions.handleEditChannel(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.share_rounded,
                title: 'Share channel',
                subtitle: 'Create a portable Debrify link for this pool.',
                tag: 'Link',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.share.handleShareChannelAsMagnet(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.delete_outline_rounded,
                title: 'Delete channel',
                subtitle: 'Remove this channel and its cached title pool.',
                tag: 'Careful',
                danger: true,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.actions.handleDeleteChannel(channel);
                },
              ),
            ],
          ),
          actions: [
            DebrifyTvDialogButton(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> showQuickPlayDialog() async {
    if (_owners.session.isBusy) {
      return;
    }

    bool avoidNsfw = _owners.settings.quickAvoidNsfw;
    String? error;
    // Create a separate controller for Quick Play to avoid sharing state with edit dialog
    final TextEditingController controller = TextEditingController();
    final FocusNode keywordFocusNode = FocusNode(
      debugLabel: 'QuickPlayKeywordsField',
    );

    await showDialog<void>(
      context: _deps.context(),
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final app = AppThemeScope.of(context);
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Quick play · no channel needed',
              title: 'Play anything',
              subtitle:
                  'Enter up to ${_owners.settings.quickPlayMaxKeywords} search terms. Nothing is saved when playback ends.',
              icon: Icons.play_arrow_rounded,
              maxWidth: 680,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvTextField(
                    controller: controller,
                    autofocus: true,
                    focusNode: keywordFocusNode,
                    textInputAction: TextInputAction.search,
                    // Shared TV shell/keyboard chrome — settings.accent,
                    // with the keyboard's own panel ground and ink.
                    accent: app.settings.accent,
                    keyboardGround: app.youtube.keyboardPanel,
                    keyboardInk: app.core.tx,
                    keyboardInkOnAccent: app.inkOn(app.settings.accent),
                    decoration: const InputDecoration(
                      labelText: 'Keywords',
                      hintText: 'Comma separated keywords',
                    ),
                    onDownArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).nextFocus();
                      }
                    },
                    onUpArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).previousFocus();
                      }
                    },
                    onChanged: (_) {
                      if (error != null) {
                        setDialogState(() => error = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchRow(
                    title: 'Avoid NSFW content',
                    subtitle: _owners.settings.viewerForcesNsfw
                        ? 'Always on for this profile'
                        : 'Best-effort filter while searching',
                    value: _owners.settings.viewerForcesNsfw || avoidNsfw,
                    onChanged: (value) {
                      // Role-locked: a child session cannot loosen it.
                      if (_owners.settings.viewerForcesNsfw) return;
                      setDialogState(() => avoidNsfw = value);
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
              actions: [
                DebrifyTvDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                DebrifyTvDialogButton(
                  label: 'Play now',
                  icon: Icons.play_arrow_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
                  onPressed: () async {
                    final keywords = controller.text.trim();
                    if (keywords.isEmpty) {
                      setDialogState(
                        () => error = 'Enter one or more keywords to continue.',
                      );
                      return;
                    }

                    if (_deps.mounted()) {
                      _deps.setState(() {
                        _owners.settings.quickStartRandom =
                            _owners.settings.startRandom;
                        _owners.settings.quickRandomStartPercent =
                            _owners.settings.randomStartPercent;
                        _owners.settings.quickHideSeekbar =
                            _owners.settings.hideSeekbar;
                        _owners.settings.quickShowChannelName =
                            _owners.settings.showChannelName;
                        _owners.settings.quickShowVideoTitle =
                            _owners.settings.showVideoTitle;
                        _owners.settings.quickHideOptions =
                            false; // Always false now
                        _owners.settings.quickHideBackButton =
                            false; // Always false now
                        _owners.settings.quickAvoidNsfw = avoidNsfw;
                        _owners.settings.quickProvider =
                            _owners.settings.provider;
                      });
                      // Copy keywords from Quick Play controller to main controller for _watch()
                      _owners.library.keywordsController.text = keywords;
                    }

                    Navigator.of(dialogContext).pop();
                    // Wait for frames to ensure UI has updated and touch events are processed
                    await Future.delayed(const Duration(milliseconds: 100));
                    await WidgetsBinding.instance.endOfFrame;
                    await WidgetsBinding.instance.endOfFrame;
                    if (_deps.mounted()) {
                      await _sections.quickPlay.watch();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    keywordFocusNode.dispose();
    controller.dispose();
  }

  Future<void> showGlobalSettingsDialog() async {
    await showDialog<void>(
      context: _deps.context(),
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Debrify TV · applies to every channel',
              title: 'Channel playback',
              subtitle:
                  'Choose the provider, filters, and starting behavior used when a channel tunes.',
              icon: Icons.settings_rounded,
              maxWidth: 920,
              maxHeightFactor: .94,
              child: _sections.settingsCard.buildSettingsCard(
                scope: DebrifyTvSettingsScope.channels,
                includeNsfwToggle: false,
                title: 'Playback rules',
                dialogSetState: setDialogState,
              ),
              actions: [
                DebrifyTvDialogButton(
                  autofocus: true,
                  label: 'Done',
                  icon: Icons.check_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
