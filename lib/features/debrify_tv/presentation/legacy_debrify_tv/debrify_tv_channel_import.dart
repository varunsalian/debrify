import 'dart:async';
import 'dart:typed_data';

import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/debrify_tv/dialogs/community_channels_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/import_channels_dialog.dart';
import 'package:debrify/services/community/community_channel_model.dart';
import 'package:debrify/services/community/community_channels_service.dart';
import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebrifyTvChannelImport {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelImport(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> handleImportChannels() async {
    if (_owners.session.isBusy) {
      return;
    }

    // Set busy to block interactions during dialog
    _deps.setState(() {
      _owners.session.isBusy = true;
    });

    final mode = await _sections.channelImport._selectImportMode();

    // Wait for frames to ensure UI has updated and touch events are processed
    if (_deps.mounted()) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (mode == null || !_deps.mounted()) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    switch (mode) {
      case ImportChannelsMode.device:
        await _sections.channelImport._handleImportChannelsFromDevice();
        break;
      case ImportChannelsMode.url:
        await _sections.urlImport.handleImportChannelsFromUrl();
        break;
      case ImportChannelsMode.community:
        await _sections.channelImport._handleImportChannelsFromCommunity();
        break;
    }
  }

  Future<ImportChannelsMode?> _selectImportMode() async {
    if (!_deps.mounted()) {
      return null;
    }

    return showDialog<ImportChannelsMode>(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (dialogContext) {
        return ImportChannelsDialog(isAndroidTv: _owners.settings.isAndroidTv);
      },
    );
  }

  Future<void> _handleImportChannelsFromDevice() async {
    // FileType.any instead of custom: Android has no MimeTypeMap entry for
    // `yaml`/`yml`/`debrify`, so a custom filter silently greys those files out
    // in the system picker (and throws "Unsupported filter" outright when every
    // extension is unmapped). The importer validates the bytes/format below.
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      withReadStream: true,
    );

    if (selection == null || selection.files.isEmpty) {
      return;
    }

    final pickedFile = selection.files.first;

    // Reject an implausibly large pick before reading it into memory.
    if (pickedFile.size > DebrifyTvZipImporter.maxPortableFileBytes) {
      _sections.feedback.showSnack(
        'Selected file is too large to import.',
        color: Colors.orange,
      );
      return;
    }
    Uint8List bytes;
    try {
      bytes = await _sections.channelImport._readPickedFileBytes(pickedFile);
    } catch (error) {
      _sections.feedback.showSnack(
        'Unable to read selected file: ${_sections.formats.formatImportError(error)}',
        color: Colors.red,
      );
      return;
    }

    if (bytes.isEmpty) {
      _sections.feedback.showSnack(
        'Selected file appears to be empty.',
        color: Colors.orange,
      );
      return;
    }

    if (!_deps.mounted()) {
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Importing channel from local storage…';
    });

    try {
      await _sections.formats.safeImportChannelBytes(
        sourceName: pickedFile.name,
        bytes: bytes,
        origin: DebrifyTvChannelImportOrigin.device,
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

  Future<void> _handleImportChannelsFromCommunity() async {
    final selectedChannels = await _sections.channelImport
        ._promptCommunityChannelsDialog();
    if (selectedChannels == null || selectedChannels.isEmpty) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    // Wait for frames to ensure UI has updated and touch events are processed
    if (_deps.mounted()) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (!_deps.mounted()) {
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Importing community channels...';
    });

    _sections.feedback.showChannelCreationDialog(
      'Importing community channels...',
    );

    int successCount = 0;
    int failureCount = 0;
    final List<String> errors = [];

    for (int i = 0; i < selectedChannels.length; i++) {
      final channel = selectedChannels[i];
      _sections.feedback.updateProgress([
        'Downloading channel ${i + 1} of ${selectedChannels.length}...',
        channel.name,
      ], replace: true);

      try {
        // Download the channel file
        final bytes = await CommunityChannelsService.downloadChannelFile(
          channel.url,
        );

        if (bytes.isEmpty) {
          throw Exception('Downloaded file is empty');
        }

        // Import using existing method (don't show dialog/summary for each channel)
        final success = await _sections.formats.importDebrifyBytes(
          channel.name,
          bytes,
          showDialog: false,
          showSummary: false,
        );

        if (success) {
          successCount++;
        } else {
          failureCount++;
          errors.add('${channel.name}: Import failed');
        }
      } catch (error) {
        failureCount++;
        errors.add('${channel.name}: ${error.toString()}');
      }
    }

    _sections.feedback.updateProgress([
      'Import complete!',
      if (successCount > 0) 'Successfully imported $successCount channel(s)',
      if (failureCount > 0) 'Failed to import $failureCount channel(s)',
      ...errors.take(5), // Show first 5 errors
    ], replace: true);

    // Show summary
    final Color snackColor = successCount > 0
        ? (failureCount > 0 ? Colors.orange : Colors.green)
        : Colors.red;

    final String message = successCount > 0
        ? 'Imported $successCount channel${successCount > 1 ? 's' : ''}${failureCount > 0 ? ', $failureCount failed' : ''}'
        : 'Failed to import channels';

    _sections.feedback.showSnack(message, color: snackColor);

    // Keep dialog open for 2 seconds to show summary
    await Future.delayed(const Duration(seconds: 2));

    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.session.isBusy = false;
        _owners.session.status = '';
      });
      _sections.feedback.closeProgressDialog();
    }
  }

  Future<List<CommunityChannel>?> _promptCommunityChannelsDialog() async {
    if (!_deps.mounted()) {
      return null;
    }

    return showDialog<List<CommunityChannel>>(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (dialogContext) {
        return CommunityChannelsDialog(
          isAndroidTv: _owners.settings.isAndroidTv,
        );
      },
    );
  }

  Future<Uint8List> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return Uint8List.fromList(file.bytes!);
    }

    final stream = file.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    }

    throw const FormatException('Unable to access file bytes.');
  }
}
