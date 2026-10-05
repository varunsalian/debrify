import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/features/debrify_tv/application/debrify_tv_byte_format.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/debrify_tv/dialogs/spotlight_dialog.dart';
import 'package:debrify/services/community/magnet_yaml_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class DebrifyTvUrlImport {
  final DebrifyTvDependencies _deps;
  DebrifyTvUrlImport(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> handleImportChannelsFromUrl() async {
    final input = await _sections.urlImport._promptImportUrl();
    if (input == null) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    final trimmedInput = input.trim();

    // Check if it's a debrify link (pasted directly)
    if (MagnetYamlService.isMagnetLink(trimmedInput)) {
      await _sections.urlImport._importDebrifyLinkDirectly(trimmedInput);
      return;
    }

    // Otherwise, treat as URL
    Uri uri;
    try {
      uri = Uri.parse(trimmedInput);
      if (!uri.hasAbsolutePath ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const FormatException('invalid');
      }
    } catch (_) {
      _sections.feedback.showSnack(
        'Enter a valid debrify:// link or http(s) URL.',
        color: Colors.red,
      );
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    if (!_deps.mounted()) {
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Downloading channel file…';
    });

    _sections.feedback.showChannelCreationDialog('Importing channel…');
    _sections.feedback.updateProgress(['Downloading channel file…']);

    try {
      final streamedResponse = await http.Request('GET', uri).send();
      if (streamedResponse.statusCode != 200) {
        throw FormatException('HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;
      final builder = BytesBuilder(copy: false);

      await for (final chunk in streamedResponse.stream) {
        builder.add(chunk);
        receivedBytes += chunk.length;
        final percent = totalBytes > 0
            ? (receivedBytes / totalBytes * 100).clamp(0, 100)
            : null;
        final progressMessage = percent != null
            ? 'Downloading… ${percent.toStringAsFixed(0)}%'
            : 'Downloading… ${formatDebrifyTvBytes(receivedBytes)}';
        _sections.feedback.updateProgress([progressMessage], replace: true);
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        _sections.feedback.updateProgress([
          'Downloaded file is empty.',
        ], replace: true);
        _sections.feedback.showSnack(
          'Downloaded file is empty.',
          color: Colors.orange,
        );
        return;
      }

      final sourceName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'channel.${_sections.urlImport._guessExtensionFromHeaders(streamedResponse.headers)}';

      _sections.feedback.updateProgress([
        'Download complete. Processing…',
      ], replace: true);

      await _sections.formats.safeImportChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: DebrifyTvChannelImportOrigin.url,
      );
    } catch (error) {
      _sections.feedback.showSnack(
        'Import failed: ${_sections.formats.formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
        _sections.feedback.closeProgressDialog();
      }
    }
  }

  Future<void> _importDebrifyLinkDirectly(String debrifyLink) async {
    if (!_deps.mounted()) {
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Decoding debrify link…';
    });

    try {
      final bytes = utf8.encode(debrifyLink);
      await _sections.formats.safeImportChannelBytes(
        sourceName: 'debrify_link',
        bytes: Uint8List.fromList(bytes),
        origin: DebrifyTvChannelImportOrigin.url,
      );
    } catch (error) {
      _sections.feedback.showSnack(
        'Import failed: ${_sections.formats.formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
        _sections.feedback.closeProgressDialog();
      }
    }
  }

  String _guessExtensionFromHeaders(Map<String, String> headers) {
    final contentType =
        headers['content-type'] ?? headers['Content-Type'] ?? 'text/plain';
    if (contentType.contains('zip')) {
      return 'zip';
    }
    if (contentType.contains('yaml') || contentType.contains('yml')) {
      return 'yaml';
    }
    return 'txt';
  }

  Future<String?> _promptImportUrl() async {
    if (!_deps.mounted()) {
      return null;
    }

    final controller = TextEditingController();
    String? errorText;
    final FocusNode urlFocusNode = FocusNode(
      debugLabel: 'ZipUrlField',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        final focusContext = node.context;
        if (focusContext == null) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(focusContext).nextFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          FocusScope.of(focusContext).previousFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    final result = await showDialog<String>(
      context: _deps.context(),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final app = AppThemeScope.of(context);
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Import · from a link',
              title: 'Paste a channel link',
              subtitle:
                  'Use a debrify:// share link or an http(s) URL to a supported channel file.',
              icon: Icons.link_rounded,
              maxWidth: 650,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvTextField(
                    controller: controller,
                    accent: app.settings.accent,
                    keyboardGround: app.youtube.keyboardPanel,
                    keyboardInk: app.core.tx,
                    keyboardInkOnAccent: app.inkOn(app.settings.accent),
                    decoration: InputDecoration(
                      labelText: 'Debrify link or file URL',
                      hintText: 'debrify://channel?... or https://...',
                      errorText: errorText,
                    ),
                    autofocus: true,
                    focusNode: urlFocusNode,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Supported: .zip · .yaml · .txt · .debrify',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      color: app.debrifyTv.textFaint,
                    ),
                  ),
                ],
              ),
              actions: [
                DebrifyTvDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                DebrifyTvDialogButton(
                  label: 'Import',
                  icon: Icons.download_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
                  onPressed: () {
                    final candidate = controller.text.trim();
                    if (candidate.isEmpty) {
                      setState(() {
                        errorText = 'Enter a link or URL to continue.';
                      });
                      return;
                    }

                    // Check if it's a debrify link (valid and accepted)
                    if (MagnetYamlService.isMagnetLink(candidate)) {
                      Navigator.of(dialogContext).pop(candidate);
                      return;
                    }

                    // Otherwise validate as http(s) URL
                    try {
                      final parsed = Uri.parse(candidate);
                      if (!parsed.hasAbsolutePath ||
                          (parsed.scheme != 'http' &&
                              parsed.scheme != 'https')) {
                        throw const FormatException('invalid');
                      }
                    } catch (_) {
                      setState(() {
                        errorText =
                            'Enter a valid debrify:// link or http(s) URL.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(candidate);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    urlFocusNode.dispose();
    return result;
  }
}
