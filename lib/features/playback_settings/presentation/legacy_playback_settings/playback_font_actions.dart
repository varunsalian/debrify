import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

typedef PlaybackFontActionsDependencies = ({
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PlaybackSubtitleState sub,
});

class PlaybackFontActions {
  final PlaybackFontActionsDependencies _deps;
  PlaybackFontActions(this._deps);

  Future<void> loadFonts() async {
    final allFonts = await SubtitleFontService.instance.getAllFonts();
    final selectedIndex = await SubtitleFontService.instance
        .getSelectedFontIndex();
    if (_deps.mounted()) {
      _deps.setState(() {
        _deps.sub.allFonts = allFonts;
        _deps.sub.subtitleFontIndex = selectedIndex;
      });
    }
  }

  Future<void> importCustomFont() async {
    try {
      // FileType.any instead of custom: Android's MIME mapping for `ttf`/`otf`
      // is unreliable and throws PlatformException("Unsupported filter"). We
      // validate the extension ourselves below.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      // Reject only a clearly-wrong extension; if the picker's display name has
      // no extension (some Android SAF providers), let the font service try it
      // rather than wrongly rejecting a valid font.
      final lowerName = file.name.toLowerCase();
      final hasExtension = lowerName.contains('.');
      if (hasExtension &&
          !lowerName.endsWith('.ttf') &&
          !lowerName.endsWith('.otf')) {
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            const SnackBar(
              content: Text('Please select a .ttf or .otf font file'),
            ),
          );
        }
        return;
      }
      if (file.path == null) {
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            const SnackBar(content: Text('Could not access selected file')),
          );
        }
        return;
      }

      final newFont = await SubtitleFontService.instance.importCustomFont(
        file.path!,
        file.name,
      );

      if (newFont != null) {
        await loadFonts();
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            SnackBar(
              content: Text('Font "${newFont.label}" imported successfully'),
            ),
          );
        }
      } else {
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            const SnackBar(content: Text('Failed to import font')),
          );
        }
      }
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Error importing font: $e')));
      }
    }
  }

  Future<void> removeCustomFont(SubtitleFont font) async {
    await SubtitleFontService.instance.removeCustomFont(font.id);
    await loadFonts();
    if (_deps.mounted()) {
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text('Font "${font.label}" removed')));
    }
  }
}
