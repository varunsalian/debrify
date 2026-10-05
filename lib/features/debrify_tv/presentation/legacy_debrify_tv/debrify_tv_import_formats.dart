import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_parsing.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/services/community/magnet_yaml_service.dart';
import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebrifyTvImportFormats {
  final DebrifyTvDependencies _deps;
  DebrifyTvImportFormats(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<bool> _importChannelBytes({
    required String sourceName,
    required Uint8List bytes,
    required DebrifyTvChannelImportOrigin origin,
  }) async {
    final type = _sections.formats._determineImportType(sourceName, bytes);
    if (type == null) {
      _sections.feedback.showSnack(
        'Unsupported file type. Select a .zip, .yaml, .txt, or .debrify file.',
        color: Colors.orange,
      );
      return false;
    }

    switch (type) {
      case DebrifyTvChannelImportType.zip:
        return await _sections.formats._importZipBytes(bytes, origin);
      case DebrifyTvChannelImportType.yaml:
        return await _sections.formats._importYamlBytes(
          sourceName,
          bytes,
          origin,
        );
      case DebrifyTvChannelImportType.text:
        return await _sections.formats._importTextBytes(sourceName, bytes);
      case DebrifyTvChannelImportType.debrify:
        return await _sections.formats.importDebrifyBytes(sourceName, bytes);
    }
  }

  Future<bool> safeImportChannelBytes({
    required String sourceName,
    required Uint8List bytes,
    required DebrifyTvChannelImportOrigin origin,
  }) async {
    try {
      return await _sections.formats._importChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: origin,
      );
    } on FormatException catch (error) {
      _sections.feedback.showSnack(error.message, color: Colors.red);
      return false;
    } catch (error) {
      // Corrupt archives throw ArchiveException/RangeError etc., not just
      // FormatException — surface them the same way instead of leaving the
      // import flow (and any progress dialog) stuck.
      _sections.feedback.showSnack(
        'Failed to import channel file: $error',
        color: Colors.red,
      );
      return false;
    }
  }

  DebrifyTvChannelImportType? _determineImportType(
    String sourceName,
    Uint8List bytes,
  ) {
    final lower = sourceName.toLowerCase();

    // Check extension first
    if (lower.endsWith('.zip')) {
      return DebrifyTvChannelImportType.zip;
    }
    if (lower.endsWith('.debrify')) {
      return DebrifyTvChannelImportType.debrify;
    }
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return DebrifyTvChannelImportType.yaml;
    }
    if (lower.endsWith('.txt')) {
      return DebrifyTvChannelImportType.text;
    }

    // Fallback: check file signature for zip
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      // PK — zip signature
      return DebrifyTvChannelImportType.zip;
    }

    // Smart content detection for unknown extensions
    try {
      final content = utf8.decode(bytes).trim();
      if (content.startsWith('debrify://')) {
        return DebrifyTvChannelImportType.debrify;
      }
    } catch (_) {
      // If UTF-8 decode fails, not a text file
    }

    return null;
  }

  Future<bool> _importZipBytes(
    Uint8List bytes,
    DebrifyTvChannelImportOrigin origin,
  ) async {
    final dialogLabel = origin == DebrifyTvChannelImportOrigin.device
        ? 'Importing zip…'
        : 'Processing zip…';

    _sections.feedback.showChannelCreationDialog(dialogLabel);
    _sections.feedback.updateProgress(['Parsing archive…']);

    final parsed = await parseZipInBackground(bytes);
    _sections.feedback.updateProgress([
      'Parsed ${parsed.channels.length} channel(s)',
      'Saving channel data…',
    ]);

    final persistence = await _sections.persistence.persistImportedZipChannels(
      parsed.channels,
    );
    _sections.feedback.updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await _sections.persistence.showZipImportSummary(parsed, persistence);
    return persistence.successes.isNotEmpty;
  }

  Future<bool> _importYamlBytes(
    String sourceName,
    Uint8List bytes,
    DebrifyTvChannelImportOrigin origin,
  ) async {
    final content = utf8.decode(bytes);
    final dialogLabel = origin == DebrifyTvChannelImportOrigin.device
        ? 'Importing YAML…'
        : 'Processing YAML…';

    _sections.feedback.showChannelCreationDialog(dialogLabel);
    _sections.feedback.updateProgress(['Parsing YAML…']);

    final channel = await parseYamlInBackground(sourceName, content);

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    _sections.feedback.updateProgress(['Saving channel…']);
    final persistence = await _sections.persistence.persistImportedZipChannels(
      parsed.channels,
    );
    _sections.feedback.updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await _sections.persistence.showZipImportSummary(parsed, persistence);
    return persistence.successes.isNotEmpty;
  }

  Future<bool> _importTextBytes(String sourceName, Uint8List bytes) async {
    final content = utf8.decode(bytes);
    final keywords = <String>[];
    final seen = <String>{};

    final lines = const LineSplitter().convert(content);
    for (final rawLine in lines) {
      final parts = rawLine.split(',');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (trimmed.length > 120) {
          throw FormatException(
            'Keyword exceeds 120 characters: "${trimmed.substring(0, trimmed.length > 40 ? 40 : trimmed.length)}${trimmed.length > 40 ? '…' : ''}"',
          );
        }
        final lower = trimmed.toLowerCase();
        if (seen.add(lower)) {
          keywords.add(trimmed);
        }
      }
    }

    if (keywords.isEmpty) {
      throw const FormatException('No keywords found in the selected file.');
    }
    if (keywords.length > 500) {
      throw const FormatException(
        'Channel files must contain 500 keywords or fewer.',
      );
    }

    final baseName = _sections.formats._stripExtension(sourceName);
    final lowerExisting = _owners.library.channels
        .map((c) => c.name.toLowerCase())
        .toSet();
    final channelName = _sections.library.resolveUniqueChannelName(
      baseName,
      lowerExisting,
    );
    final now = DateTime.now();
    final channel = DebrifyTvChannel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: channelName,
      keywords: keywords,
      avoidNsfw: true,
      channelNumber: 0,
      createdAt: now,
      updatedAt: now,
    );

    await _sections.save.createOrUpdateChannel(channel, isEdit: false);
    _sections.feedback.showSnack(
      'Imported "${channel.name}"',
      color: Colors.green,
    );
    return true;
  }

  Future<bool> importDebrifyBytes(
    String sourceName,
    Uint8List bytes, {
    bool showDialog = true,
    bool showSummary = true,
  }) async {
    final content = utf8.decode(bytes).trim();

    // Validate debrify link format
    if (!MagnetYamlService.isMagnetLink(content)) {
      throw const FormatException('Not a valid Debrify link.');
    }

    if (showDialog) {
      _sections.feedback.showChannelCreationDialog('Importing channel…');
    }
    _sections.feedback.updateProgress(['Decoding debrify link…']);

    // Decode debrify link
    final result = MagnetYamlService.decode(content);

    _sections.feedback.updateProgress(['Parsing channel data…']);

    // Parse the decoded YAML
    final channel = await parseYamlInBackground(
      result.channelName,
      result.yamlContent,
    );

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    _sections.feedback.updateProgress(['Saving channel…']);
    final persistence = await _sections.persistence.persistImportedZipChannels(
      parsed.channels,
    );
    _sections.feedback.updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    if (showSummary) {
      await _sections.persistence.showZipImportSummary(parsed, persistence);
    }
    return persistence.successes.isNotEmpty;
  }

  String _stripExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0) {
      return name.trim();
    }
    return name.substring(0, dotIndex).trim();
  }

  String formatImportError(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    return error.toString().replaceFirst('Exception: ', '').trim();
  }
}
