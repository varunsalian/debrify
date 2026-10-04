import 'package:debrify/features/iptv_settings/presentation/iptv_settings_tv_button.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsSourceFormsDeps = ({
  IptvSettingsInputOwner inputOwner,
  IptvSettingsFocusOwner focusOwner,
  void Function(FocusNode node) focusAndReveal,
  Future<void> Function() addPlaylist,
  IptvSettingsLayoutOwner layoutOwner,
  IptvSettingsSourcesOwner sourcesOwner,
  BuildContext Function() context,
  Future<void> Function() importFromFile,
  Future<void> Function() addXtreamCodes,
});

class IptvSettingsSourceForms {
  IptvSettingsSourceForms(this._deps);
  final IptvSettingsSourceFormsDeps _deps;

  Widget buildUrlTabContent() {
    return Column(
      children: [
        // Name input
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: TvTextField(
            controller: _deps.inputOwner.nameController,
            focusNode: _deps.focusOwner.nameInputFocusNode,
            labelText: 'Playlist Name',
            hintText: 'e.g., My IPTV',
            prefixIcon: const Icon(Icons.label_outline),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                _deps.focusAndReveal(_deps.focusOwner.urlInputFocusNode),
            // Explicit exits: UP targets the SELECTED tab (geometric search
            // from a full-width field center-lands on the middle tab).
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.urlTabFocusNode),
            onDownArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.urlInputFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // URL input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: TvTextField(
            controller: _deps.inputOwner.urlController,
            focusNode: _deps.focusOwner.urlInputFocusNode,
            labelText: 'Playlist URL',
            hintText: 'https://example.com/playlist.m3u',
            prefixIcon: const Icon(Icons.link),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                _deps.focusAndReveal(_deps.focusOwner.epgUrlInputFocusNode),
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.nameInputFocusNode),
            onDownArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.epgUrlInputFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // EPG URL input (optional). Playlists that declare url-tvg in their
        // own header don't need it; this overrides when both exist.
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: TvTextField(
            controller: _deps.inputOwner.epgUrlController,
            focusNode: _deps.focusOwner.epgUrlInputFocusNode,
            labelText: 'EPG URL (XMLTV, optional)',
            hintText: 'https://example.com/guide.xml.gz',
            prefixIcon: const Icon(Icons.calendar_view_day_outlined),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              // IME "done" unfocuses the field — park DPAD on the button so
              // focus isn't stranded on the bare scope while the add runs.
              _deps.focusOwner.addButtonFocusNode.requestFocus();
              _deps.addPlaylist();
            },
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.urlInputFocusNode),
            onDownArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.addButtonFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Add button
        FocusTraversalOrder(
          // 4.5: after the EPG field, before the playlist tiles at 5.0 + i.
          order: const NumericFocusOrder(4.5),
          child: Align(
            alignment: Alignment.centerRight,
            child: IptvSettingsTvButton(
              focusNode: _deps.focusOwner.addButtonFocusNode,
              icon: _deps.inputOwner.isAdding
                  ? Icons.hourglass_empty
                  : Icons.add,
              label: _deps.inputOwner.isAdding ? 'Adding...' : 'Add Playlist',
              onPressed: _deps.inputOwner.isAdding ? () {} : _deps.addPlaylist,
              onUpArrow: () =>
                  _deps.focusAndReveal(_deps.focusOwner.epgUrlInputFocusNode),
              onDownArrow:
                  !_deps.layoutOwner.twoPaneActive &&
                      _deps.sourcesOwner.playlists.isNotEmpty &&
                      _deps.focusOwner.playlistFocusNodes.isNotEmpty
                  ? () => _deps.focusAndReveal(
                      _deps.focusOwner.playlistFocusNodes[0],
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildFileTabContent() {
    final t = AppThemeScope.of(_deps.context()).settings;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.folder_open,
          size: 48,
          color: t.accent2.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 16),
        Text(
          'Select an M3U or M3U8 file from your device',
          style: TextStyle(fontSize: 14, color: t.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: IptvSettingsTvButton(
            focusNode: _deps.focusOwner.importFileButtonFocusNode,
            icon: Icons.file_open,
            label: 'Browse Files',
            onPressed: _deps.importFromFile,
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.fileTabFocusNode),
            onDownArrow:
                !_deps.layoutOwner.twoPaneActive &&
                    _deps.sourcesOwner.playlists.isNotEmpty &&
                    _deps.focusOwner.playlistFocusNodes.isNotEmpty
                ? () => _deps.focusAndReveal(
                    _deps.focusOwner.playlistFocusNodes[0],
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget buildXcTabContent() {
    return Column(
      children: [
        // Playlist name input (optional). Blank falls back to username@host.
        FocusTraversalOrder(
          order: const NumericFocusOrder(1.9),
          child: TvTextField(
            controller: _deps.inputOwner.xcNameController,
            focusNode: _deps.focusOwner.xcNameFocusNode,
            labelText: 'Playlist Name (optional)',
            hintText: 'e.g., My Provider',
            prefixIcon: const Icon(Icons.label_outline),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                _deps.focusAndReveal(_deps.focusOwner.xcServerFocusNode),
            // UP targets the SELECTED tab (geometric search from a full-width
            // field center-lands on the middle tab).
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcTabFocusNode),
            onDownArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcServerFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Server URL input
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: TvTextField(
            controller: _deps.inputOwner.xcServerController,
            focusNode: _deps.focusOwner.xcServerFocusNode,
            labelText: 'Server URL',
            hintText: 'http://example.com:8080',
            prefixIcon: const Icon(Icons.dns),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                _deps.focusAndReveal(_deps.focusOwner.xcUsernameFocusNode),
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcNameFocusNode),
            onDownArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcUsernameFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Username input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: TvTextField(
            controller: _deps.inputOwner.xcUsernameController,
            focusNode: _deps.focusOwner.xcUsernameFocusNode,
            labelText: 'Username',
            hintText: 'your username',
            prefixIcon: const Icon(Icons.person),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                _deps.focusAndReveal(_deps.focusOwner.xcPasswordFocusNode),
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcServerFocusNode),
            onDownArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcPasswordFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Password input
        FocusTraversalOrder(
          order: const NumericFocusOrder(3.5),
          child: TvTextField(
            controller: _deps.inputOwner.xcPasswordController,
            focusNode: _deps.focusOwner.xcPasswordFocusNode,
            labelText: 'Password',
            hintText: 'your password',
            prefixIcon: const Icon(Icons.lock),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              // IME "done" unfocuses the field — park DPAD on the button so
              // focus isn't stranded on the bare scope while the login runs.
              _deps.focusOwner.xcLoginButtonFocusNode.requestFocus();
              _deps.addXtreamCodes();
            },
            onUpArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcUsernameFocusNode),
            onDownArrow: () =>
                _deps.focusAndReveal(_deps.focusOwner.xcLoginButtonFocusNode),
          ),
        ),
        const SizedBox(height: 12),

        // Login button
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: Align(
            alignment: Alignment.centerRight,
            child: IptvSettingsTvButton(
              focusNode: _deps.focusOwner.xcLoginButtonFocusNode,
              icon: _deps.inputOwner.isXcAdding
                  ? Icons.hourglass_empty
                  : Icons.login,
              label: _deps.inputOwner.isXcAdding
                  ? 'Logging in...'
                  : 'Login & Add',
              onPressed: _deps.inputOwner.isXcAdding
                  ? () {}
                  : _deps.addXtreamCodes,
              onUpArrow: () =>
                  _deps.focusAndReveal(_deps.focusOwner.xcPasswordFocusNode),
              onDownArrow:
                  !_deps.layoutOwner.twoPaneActive &&
                      _deps.sourcesOwner.playlists.isNotEmpty &&
                      _deps.focusOwner.playlistFocusNodes.isNotEmpty
                  ? () => _deps.focusAndReveal(
                      _deps.focusOwner.playlistFocusNodes[0],
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
