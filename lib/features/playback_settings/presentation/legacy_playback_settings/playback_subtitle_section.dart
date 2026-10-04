import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/playback_checkbox_tile.dart';
import 'package:debrify/features/playback_settings/presentation/playback_setting_dropdown.dart';
import 'package:debrify/screens/settings/subtitle_priority_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef PlaybackSubtitleSectionDependencies = ({
  BuildContext Function() context,
  Widget Function(String title, String subtitle, List<Widget> children)
  defaultsCard,
  Future<void> Function() importCustomFont,
  Future<void> Function(SubtitleFont font) removeCustomFont,
  Future<void> Function(String? languageCode) setDefaultSubtitleLanguage,
  Future<void> Function(bool enabled) setSubtitleAutoSync,
  Future<void> Function(int index) setSubtitleBgIndex,
  Future<void> Function(bool value) setSubtitleBold,
  Future<void> Function(int index) setSubtitleColorIndex,
  Future<void> Function(int index) setSubtitleFontIndex,
  Future<void> Function(bool enabled) setSubtitleForcedOnly,
  Future<void> Function(bool enabled) setSubtitleOnlyForeignAudio,
  Future<void> Function(int index) setSubtitleSizeIndex,
  Future<void> Function(int index) setSubtitleStyleIndex,
  PlaybackSubtitleState sub,
  PlaybackSubtitleRowsState subRows,
});

class PlaybackSubtitleSection {
  final PlaybackSubtitleSectionDependencies _deps;
  PlaybackSubtitleSection(this._deps);

  // Subtitle language options: (code, label)
  static const List<(String?, String)> subtitleLanguageOptions = [
    (null, 'No Preference'),
    ('off', 'Off'),
    ('en', 'English'),
    ('es', 'Spanish'),
    ('fr', 'French'),
    ('de', 'German'),
    ('it', 'Italian'),
    ('pt', 'Portuguese'),
    ('pt-BR', 'Portuguese (Brazil)'),
    ('ru', 'Russian'),
    ('ja', 'Japanese'),
    ('ko', 'Korean'),
    ('zh', 'Chinese'),
    ('ar', 'Arabic'),
    ('hi', 'Hindi'),
    ('te', 'Telugu'),
    ('nl', 'Dutch'),
    ('pl', 'Polish'),
    ('tr', 'Turkish'),
    ('sv', 'Swedish'),
    ('da', 'Danish'),
    ('no', 'Norwegian'),
    ('fi', 'Finnish'),
    ('et', 'Estonian'),
    ('hr', 'Croatian'),
    ('sr', 'Serbian'),
    ('bs', 'Bosnian'),
    ('mk', 'Macedonian'),
    ('sl', 'Slovenian'),
    ('cs', 'Czech'),
    ('sk', 'Slovak'),
    ('hu', 'Hungarian'),
    ('ro', 'Romanian'),
    ('bg', 'Bulgarian'),
    ('uk', 'Ukrainian'),
    ('el', 'Greek'),
    ('lv', 'Latvian'),
    ('lt', 'Lithuanian'),
    ('he', 'Hebrew'),
    ('fa', 'Persian'),
    ('th', 'Thai'),
    ('vi', 'Vietnamese'),
    ('id', 'Indonesian'),
    ('ms', 'Malay'),
    ('bn', 'Bengali'),
    ('ta', 'Tamil'),
    ('mr', 'Marathi'),
    ('gu', 'Gujarati'),
    ('kn', 'Kannada'),
    ('ml', 'Malayalam'),
    ('pa', 'Punjabi'),
  ];

  int get subtitleLanguageIndex {
    final idx = subtitleLanguageOptions.indexWhere(
      (opt) => opt.$1 == _deps.sub.defaultSubtitleLanguage,
    );
    return idx >= 0 ? idx : 0;
  }

  List<Widget> subtitleSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      SettingsSection(
        title: '',
        children: [
          SettingsTile(
            icon: Icons.low_priority_rounded,
            title: 'Subtitle priority',
            subtitle:
                'Choose the order of embedded subtitles and subtitle addons',
            onTap: () async {
              await pushSettingsPage(
                _deps.context(),
                const SubtitlePriorityPage(),
              );
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      _deps.defaultsCard(
        'Subtitle defaults',
        'Preferred language and timing for the built-in player',
        [
          // Default Subtitle Language
          buildSettingDropdown(
            _deps.context(),
            label: 'Default Subtitle',
            value: subtitleLanguageIndex,
            items: subtitleLanguageOptions.map((opt) => opt.$2).toList(),
            onChanged: (index) => _deps.setDefaultSubtitleLanguage(
              subtitleLanguageOptions[index].$1,
            ),
            focusNode: _deps.subRows.defaultSubtitleLangFocusNode,
            isFocused: _deps.subRows.defaultSubtitleLangFocused,
          ),

          const SizedBox(height: 4),
          buildCheckboxTile(
            _deps.context(),
            title: 'Subtitles when audio differs',
            subtitle:
                'Choose a Default Audio language in Playback → Audio. '
                'Subtitles stay off for matching or unknown audio; '
                'manual subtitle choices take priority.',
            value: _deps.sub.subtitleOnlyForeignAudio,
            onChanged: _deps.setSubtitleOnlyForeignAudio,
            focusNode: _deps.subRows.subtitleOnlyForeignAudioFocusNode,
            isFocused: _deps.subRows.subtitleOnlyForeignAudioFocused,
          ),

          const SizedBox(height: 4),
          buildCheckboxTile(
            _deps.context(),
            title: 'Forced subtitles only',
            subtitle:
                'Automatically use embedded tracks marked forced in your Default Subtitle language '
                '(English if unset). No match means off; Default Subtitle Off disables it. '
                'Overrides Subtitles when audio differs; manual choices take priority.',
            value: _deps.sub.subtitleForcedOnly,
            onChanged: _deps.setSubtitleForcedOnly,
            focusNode: _deps.subRows.subtitleForcedOnlyFocusNode,
            isFocused: _deps.subRows.subtitleForcedOnlyFocused,
          ),

          // Only platforms whose bundled native player is
          // built with the required passive analysis filters
          // (see PlatformUtil.supportsSubtitleAutoSync).
          if (PlatformUtil.supportsSubtitleAutoSync) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              _deps.context(),
              title: 'Auto-sync addon subtitles (experimental)',
              subtitle:
                  'Quietly align downloaded subtitles to the audio '
                  'as you watch. Applies only on a confident match; '
                  'manual timing always wins.',
              value: _deps.sub.subtitleAutoSync,
              onChanged: _deps.setSubtitleAutoSync,
              focusNode: _deps.subRows.subtitleAutoSyncFocusNode,
              isFocused: _deps.subRows.subtitleAutoSyncFocused,
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      // Subtitle Appearance
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subtitle Appearance',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Customize how subtitles look',
                style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
              ),
              const SizedBox(height: 16),

              // Size
              buildSettingDropdown(
                _deps.context(),
                label: 'Size',
                value: _deps.sub.subtitleSizeIndex,
                items: SubtitleSize.options.map((o) => o.label).toList(),
                onChanged: (index) => _deps.setSubtitleSizeIndex(index),
                focusNode: _deps.subRows.subtitleSizeFocusNode,
                isFocused: _deps.subRows.subtitleSizeFocused,
              ),
              const SizedBox(height: 12),

              // Style
              buildSettingDropdown(
                _deps.context(),
                label: 'Style',
                value: _deps.sub.subtitleStyleIndex,
                items: SubtitleStyle.options.map((o) => o.label).toList(),
                onChanged: (index) => _deps.setSubtitleStyleIndex(index),
                focusNode: _deps.subRows.subtitleStyleFocusNode,
                isFocused: _deps.subRows.subtitleStyleFocused,
              ),
              const SizedBox(height: 12),

              // Color
              buildSettingDropdown(
                _deps.context(),
                label: 'Color',
                value: _deps.sub.subtitleColorIndex,
                items: SubtitleColor.options.map((o) => o.label).toList(),
                onChanged: (index) => _deps.setSubtitleColorIndex(index),
                focusNode: _deps.subRows.subtitleColorFocusNode,
                isFocused: _deps.subRows.subtitleColorFocused,
              ),
              const SizedBox(height: 12),

              // Background
              buildSettingDropdown(
                _deps.context(),
                label: 'Background',
                value: _deps.sub.subtitleBgIndex,
                items: SubtitleBackground.options.map((o) => o.label).toList(),
                onChanged: (index) => _deps.setSubtitleBgIndex(index),
                focusNode: _deps.subRows.subtitleBgFocusNode,
                isFocused: _deps.subRows.subtitleBgFocused,
              ),
              const SizedBox(height: 12),

              // Font
              buildSettingDropdown(
                _deps.context(),
                label: 'Font',
                value: _deps.sub.subtitleFontIndex,
                items: _deps.sub.allFonts
                    .map((f) => f.isCustom ? '${f.label} (Custom)' : f.label)
                    .toList(),
                onChanged: (index) => _deps.setSubtitleFontIndex(index),
                focusNode: _deps.subRows.subtitleFontFocusNode,
                isFocused: _deps.subRows.subtitleFontFocused,
              ),
              const SizedBox(height: 12),

              // Bold
              buildSettingDropdown(
                _deps.context(),
                label: 'Bold',
                value: _deps.sub.subtitleBold ? 1 : 0,
                items: const ['Off', 'On'],
                onChanged: (index) => _deps.setSubtitleBold(index == 1),
                focusNode: _deps.subRows.subtitleBoldFocusNode,
                isFocused: _deps.subRows.subtitleBoldFocused,
              ),

              // Import custom font button (always visible)
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _deps.importCustomFont,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import Custom Font (TTF/OTF)'),
                  // Default focus overlay is too faint for TV —
                  // paint an explicit accent ring + lit fill.
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.focused) ? t.panel2 : null,
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.focused)
                          ? BorderSide(color: t.accent, width: 2)
                          : null,
                    ),
                  ),
                ),
              ),

              // List of custom fonts with delete buttons
              if (_deps.sub.allFonts.any((f) => f.isCustom)) ...[
                const SizedBox(height: 12),
                Text(
                  'Custom Fonts',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: t.dim,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                ..._deps.sub.allFonts
                    .where((f) => f.isCustom)
                    .map(
                      (font) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.text_fields, size: 16, color: t.dim),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                font.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      _deps
                                              .sub
                                              .allFonts[_deps
                                                  .sub
                                                  .subtitleFontIndex]
                                              .id ==
                                          font.id
                                      ? t.accent
                                      : t.dim,
                                  fontWeight:
                                      _deps
                                              .sub
                                              .allFonts[_deps
                                                  .sub
                                                  .subtitleFontIndex]
                                              .id ==
                                          font.id
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _deps.removeCustomFont(font),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: t.danger,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              tooltip: 'Remove font',
                              // DPAD focus must be unmistakable.
                              style: ButtonStyle(
                                backgroundColor:
                                    WidgetStateProperty.resolveWith(
                                      (s) => s.contains(WidgetState.focused)
                                          ? t.panel2
                                          : null,
                                    ),
                                side: WidgetStateProperty.resolveWith(
                                  (s) => s.contains(WidgetState.focused)
                                      ? BorderSide(color: t.accent, width: 2)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],

              const SizedBox(height: 16),

              // Preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Builder(
                    builder: (context) {
                      final previewSize =
                          SubtitleSize
                              .options[_deps.sub.subtitleSizeIndex]
                              .sizePx *
                          0.4;
                      final data = SubtitleSettingsData(
                        sizeIndex: _deps.sub.subtitleSizeIndex,
                        styleIndex: _deps.sub.subtitleStyleIndex,
                        colorIndex: _deps.sub.subtitleColorIndex,
                        bgIndex: _deps.sub.subtitleBgIndex,
                        bold: _deps.sub.subtitleBold,
                        fontIndex: _deps.sub.subtitleFontIndex,
                        fontFamily:
                            _deps.sub.subtitleFontIndex <
                                _deps.sub.allFonts.length
                            ? _deps
                                  .sub
                                  .allFonts[_deps.sub.subtitleFontIndex]
                                  .fontFamily
                            : null,
                      );
                      return Text(
                        'Sample Subtitle',
                        // Built by the same code the player uses,
                        // at the preview's size — a preview that
                        // styles text its own way is a preview
                        // that can lie about bold.
                        style: data.buildTextStyle(fontSizePx: previewSize),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
