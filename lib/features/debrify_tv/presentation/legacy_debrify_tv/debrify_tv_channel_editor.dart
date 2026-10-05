import 'dart:async';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/debrify_tv_choice_chip.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

class DebrifyTvChannelEditor {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelEditor(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  bool _addKeywordsToList(
    String raw,
    List<String> keywordList,
    void Function(void Function()) setState,
  ) {
    if (raw.isEmpty) return false;
    final parsed = _sections.library.parseKeywords(raw.replaceAll('\n', ','));
    if (parsed.isEmpty) return false;
    var limitReached = false;
    setState(() {
      for (final kw in parsed) {
        if (keywordList.length >= DebrifyTvConstants.maxChannelKeywords) {
          limitReached = true;
          break;
        }
        final exists = keywordList.any(
          (existing) => existing.toLowerCase() == kw.toLowerCase(),
        );
        if (!exists) {
          keywordList.add(kw);
        }
      }
    });
    return limitReached ||
        keywordList.length >= DebrifyTvConstants.maxChannelKeywords;
  }

  Future<DebrifyTvChannel?> openChannelDialog({
    DebrifyTvChannel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final keywordInputController = TextEditingController();
    FocusNode? channelNameFocus;
    FocusNode? channelKeywordFocus;
    if (_owners.settings.isAndroidTv) {
      channelNameFocus = FocusNode(debugLabel: 'DebrifyTVChannelName');
      channelKeywordFocus = FocusNode(debugLabel: 'DebrifyTVChannelKeyword');
    }
    final List<String> keywordList = [];
    final seenKeywords = <String>{};
    final initialKeywords = existing != null
        ? existing.keywords
        : const <String>[];
    for (final kw in initialKeywords) {
      final trimmed = kw.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (seenKeywords.contains(lower)) continue;
      seenKeywords.add(lower);
      keywordList.add(trimmed);
      if (keywordList.length >= DebrifyTvConstants.maxChannelKeywords) break;
    }
    // Channel defaults - keep NSFW preference per channel only
    bool avoidNsfw = existing?.avoidNsfw ?? true;
    String? error;

    DebrifyTvChannel? result;
    try {
      result = await showDialog<DebrifyTvChannel>(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final app = AppThemeScope.of(context);
              final tv = app.debrifyTv;
              Future<void> submit() async {
                final pendingRaw = keywordInputController.text.trim();
                if (pendingRaw.isNotEmpty) {
                  final pendingKeywords = _sections.library.parseKeywords(
                    pendingRaw,
                  );
                  for (final rawKw in pendingKeywords) {
                    final trimmedKw = rawKw.trim();
                    if (trimmedKw.isEmpty) {
                      continue;
                    }
                    final alreadyPresent = keywordList.any(
                      (existing) =>
                          existing.toLowerCase() == trimmedKw.toLowerCase(),
                    );
                    if (alreadyPresent) {
                      continue;
                    }
                    if (keywordList.length >=
                        DebrifyTvConstants.maxChannelKeywords) {
                      setModalState(() {
                        error =
                            'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
                      });
                      return;
                    }
                    keywordList.add(trimmedKw);
                  }
                  keywordInputController.clear();
                }

                final name = nameController.text.trim();
                final keywords = <String>[];
                final seen = <String>{};
                for (final raw in keywordList) {
                  final trimmed = raw.trim();
                  if (trimmed.isEmpty) continue;
                  final lower = trimmed.toLowerCase();
                  if (seen.contains(lower)) continue;
                  seen.add(lower);
                  keywords.add(trimmed);
                }
                if (name.isEmpty) {
                  setModalState(() {
                    error = 'Give the channel a name';
                  });
                  return;
                }
                if (keywords.isEmpty) {
                  setModalState(() {
                    error = 'Add at least one keyword';
                  });
                  return;
                }
                if (keywords.length > DebrifyTvConstants.maxChannelKeywords) {
                  setModalState(() {
                    error =
                        'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
                  });
                  return;
                }
                final now = DateTime.now();
                final channel = DebrifyTvChannel(
                  id:
                      existing?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name,
                  keywords: keywords,
                  avoidNsfw: avoidNsfw, // Channel's own NSFW setting
                  channelNumber: existing?.channelNumber ?? 0,
                  createdAt: existing?.createdAt ?? now,
                  updatedAt: now,
                );
                Navigator.of(dialogContext).pop(channel);
              }

              return DebrifyTvSpotlightDialog(
                eyebrow: existing == null
                    ? 'Channel editor · new'
                    : 'Channel editor · ${existing.channelNumber.toString().padLeft(2, '0')}',
                title: existing == null ? 'Create a channel' : 'Edit channel',
                subtitle:
                    'Keywords are search terms. Add one or several and Debrify will pool the results.',
                icon: Icons.tv_rounded,
                maxWidth: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TvTextField(
                      controller: nameController,
                      focusNode: channelNameFocus,
                      autofocus: _owners.settings.isAndroidTv,
                      textCapitalization: TextCapitalization.words,
                      // The shared TV shell/keyboard chrome follows
                      // settings.accent. NOT debrifyTv.accent: legacy
                      // paints that the channel grid's Netflix red, while
                      // the keyboard's highlight has always been violet.
                      accent: app.settings.accent,
                      keyboardGround: app.youtube.keyboardPanel,
                      keyboardInk: app.core.tx,
                      keyboardInkOnAccent: app.inkOn(app.settings.accent),
                      decoration: const InputDecoration(
                        labelText: 'Channel name',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                      onDownArrow: () => channelKeywordFocus?.requestFocus(),
                      onUpArrow: () {
                        final ctx = channelNameFocus?.context;
                        if (ctx != null) {
                          FocusScope.of(ctx).previousFocus();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Keywords (${keywordList.length}/${DebrifyTvConstants.maxChannelKeywords})',
                      style: TextStyle(
                        color: tv.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tip: type a keyword and press Enter. Add multiples by separating with commas.',
                      style: TextStyle(color: tv.textFaint, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...keywordList.map(
                          (keyword) => debrifyTvChoiceChip(
                            label: keyword,
                            selected: false,
                            enabled: true,
                            trailingIcon: Icons.close_rounded,
                            onPressed: () {
                              setModalState(() {
                                keywordList.remove(keyword);
                                if (error != null &&
                                    error!.contains(
                                      '${DebrifyTvConstants.maxChannelKeywords} keywords',
                                    ) &&
                                    keywordList.length <
                                        DebrifyTvConstants.maxChannelKeywords) {
                                  error = null;
                                }
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: TvTextField(
                            controller: keywordInputController,
                            focusNode: channelKeywordFocus,
                            decoration: const InputDecoration(
                              hintText: 'Add keyword',
                              prefixIcon: Icon(Icons.add_rounded),
                            ),
                            style: TextStyle(color: app.core.tx),
                            // Shared TV shell/keyboard chrome — see the
                            // channel-name field above.
                            accent: app.settings.accent,
                            keyboardGround: app.youtube.keyboardPanel,
                            keyboardInk: app.core.tx,
                            keyboardInkOnAccent: app.inkOn(app.settings.accent),
                            onUpArrow: () => channelNameFocus?.requestFocus(),
                            onDownArrow: () {
                              final ctx = channelKeywordFocus?.context;
                              if (ctx != null) {
                                FocusScope.of(ctx).nextFocus();
                              }
                            },
                            onSubmitted: (value) {
                              final limitReached = _sections.editor
                                  ._addKeywordsToList(
                                    value,
                                    keywordList,
                                    setModalState,
                                  );
                              keywordInputController.clear();
                              if (limitReached) {
                                setModalState(() {
                                  error =
                                      'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
                                });
                              } else if (error != null &&
                                  error!.contains(
                                    '${DebrifyTvConstants.maxChannelKeywords} keywords',
                                  )) {
                                setModalState(() {
                                  error = null;
                                });
                              }
                            },
                            onChanged: (value) {
                              if (value.contains(',')) {
                                final limitReached = _sections.editor
                                    ._addKeywordsToList(
                                      value,
                                      keywordList,
                                      setModalState,
                                    );
                                keywordInputController.clear();
                                if (limitReached) {
                                  setModalState(() {
                                    error =
                                        'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
                                  });
                                } else if (error != null &&
                                    error!.contains(
                                      '${DebrifyTvConstants.maxChannelKeywords} keywords',
                                    )) {
                                  setModalState(() {
                                    error = null;
                                  });
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    DebrifyTvDialogSection(
                      label: 'Channel settings',
                      child: SwitchRow(
                        title: 'Avoid NSFW content',
                        subtitle: _owners.settings.viewerForcesNsfw
                            ? 'Always on for this profile'
                            : 'Best-effort filter while building this channel',
                        value: _owners.settings.viewerForcesNsfw || avoidNsfw,
                        onChanged: (v) {
                          if (_owners.settings.viewerForcesNsfw) return;
                          setModalState(() => avoidNsfw = v);
                        },
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
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
                    label: 'Save channel',
                    icon: Icons.check_rounded,
                    tone: DebrifyTvDialogButtonTone.primary,
                    onPressed: submit,
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      void disposer() {
        channelNameFocus?.dispose();
        channelKeywordFocus?.dispose();
        nameController.dispose();
        keywordInputController.dispose();
      }

      if (_deps.mounted()) {
        WidgetsBinding.instance.addPostFrameCallback((_) => disposer());
      } else {
        disposer();
      }
    }

    return result;
  }
}
