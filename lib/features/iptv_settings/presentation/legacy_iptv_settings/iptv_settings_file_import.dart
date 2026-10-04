import 'package:debrify/features/iptv_settings/presentation/iptv_settings_playlist_name_dialog.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/utils/m3u_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsFileImportDeps = ({
  Future<void> Function(Future<void> Function() body) runProfileAction,
  void Function(String message, {bool isError}) showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
  IptvSettingsSourcesOwner sourcesOwner,
  void Function(VoidCallback) setState,
  void Function() ensureFocusNodes,
});

class IptvSettingsFileImport {
  IptvSettingsFileImport(this._deps);
  final IptvSettingsFileImportDeps _deps;

  Future<void> importFromFile() =>
      _deps.runProfileAction(importFromFileForProfile);

  Future<void> importFromFileForProfile() async {
    try {
      // FileType.any instead of custom extensions: Android's MIME mapping for
      // .m3u/.m3u8 is unreliable and can leave valid files unselectable in the
      // picker. The extension is validated below instead.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final file = result.files.first;
      final fileName = file.name.toLowerCase();

      // Validate extension
      if (!fileName.endsWith('.m3u') && !fileName.endsWith('.m3u8')) {
        _deps.showSnackBar('Please select an M3U or M3U8 file');
        return;
      }

      // Read file content
      final Uint8List? fileBytes =
          file.bytes ??
          (file.path != null ? await file.xFile.readAsBytes() : null);
      if (fileBytes == null) {
        _deps.showSnackBar('Could not read file content');
        return;
      }

      // Decode as UTF-8 so non-ASCII channel names survive; falls back to
      // latin1 for legacy playlists.
      final content = M3uParser.decodeBytes(fileBytes);

      // Validate file size (warn for >5MB)
      if (content.length > 5 * 1024 * 1024) {
        _deps.showSnackBar(
          'File is very large (>${(content.length / 1024 / 1024).toStringAsFixed(1)}MB). This may cause issues.',
        );
      }

      // Parse to validate content (off the UI isolate for large files)
      final parseResult = await IptvService.instance.parseContent(content);

      if (parseResult.hasError) {
        _deps.showSnackBar('Failed to parse playlist: ${parseResult.error}');
        return;
      }

      if (parseResult.isEmpty) {
        _deps.showSnackBar('Playlist is empty or invalid');
        return;
      }

      // Extract default name from filename (without extension)
      String defaultName = file.name;
      if (defaultName.toLowerCase().endsWith('.m3u8')) {
        defaultName = defaultName.substring(0, defaultName.length - 5);
      } else if (defaultName.toLowerCase().endsWith('.m3u')) {
        defaultName = defaultName.substring(0, defaultName.length - 4);
      }

      // Show dialog to get playlist name
      if (!_deps.mounted()) return;
      final playlistName = await showDialog<String>(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (context) => Theme(
          data: settingsPageTheme(context),
          child: IptvSettingsPlaylistNameDialog(
            defaultName: defaultName,
            channelCount: parseResult.channels.length,
            existingNames: _deps.sourcesOwner.playlists
                .map((p) => p.name)
                .toSet(),
          ),
        ),
      );

      // User cancelled
      if (playlistName == null || playlistName.isEmpty || !_deps.mounted()) {
        return;
      }

      // Create new playlist with content
      final playlist = IptvPlaylist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: playlistName,
        url: '', // Empty URL for file-based playlists
        content: content,
        addedAt: DateTime.now(),
      );

      final newPlaylists = [..._deps.sourcesOwner.playlists, playlist];
      final savedPlaylists =
          await IptvPlaylistStorage.setIptvPlaylistsAndReload(
            newPlaylists,
            forSettings: true,
          );
      if (!_deps.mounted()) return;

      _deps.setState(() {
        _deps.sourcesOwner.playlists = savedPlaylists;
      });
      _deps.ensureFocusNodes();

      _deps.showSnackBar(
        'Imported "$playlistName" (${parseResult.channels.length} channels)',
        isError: false,
      );
    } catch (e) {
      _deps.showSnackBar('Failed to import file: $e');
    }
  }
}
