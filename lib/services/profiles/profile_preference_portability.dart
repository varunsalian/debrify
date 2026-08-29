import 'dart:convert';

import 'profile_preferences.dart';

/// Portability policy for encrypted profile backups and authenticated profile
/// transfers.
///
/// Platform-specific preferences are not rejected merely for naming a platform:
/// renderer, layout, keyboard, and trusted-player choices are passive and are
/// ignored by platforms that do not consume them. The boundary is capability,
/// not spelling — device grants, filesystem locations, and executable command
/// templates never become active on a different installation.
abstract final class ProfilePreferencePortability {
  static bool allowsKey(
    String key, {
    bool includeCredentialEngineSettings = false,
  }) {
    if (key.isEmpty || key.length > 256) return false;
    final credentialShaped = _credentialPattern.hasMatch(key);
    final portableEngineCredential =
        includeCredentialEngineSettings && key.startsWith('engine_');
    if ((credentialShaped && !portableEngineCredential) ||
        _legacyResourceAuthorityKeys.contains(key) ||
        DevicePreferences.allowedKeys.contains(key) ||
        key.startsWith('remote_')) {
      return false;
    }
    if (_nonPortableKeys.contains(key)) return false;
    if (key.startsWith('tvmaze_cache_') ||
        key.startsWith('tvmaze_timestamp_')) {
      return false;
    }
    return true;
  }

  /// Returns the value safe to place in a portable profile namespace.
  ///
  /// A null value is deliberate: it removes an unsafe/device-local value from
  /// a merge restore instead of leaving the destination's prior value behind.
  static ({bool include, Object? value}) prepareValue(
    String key,
    Object? value, {
    bool includeCredentialEngineSettings = false,
  }) {
    if (!allowsKey(
      key,
      includeCredentialEngineSettings: includeCredentialEngineSettings,
    )) {
      return (include: false, value: null);
    }
    if (_deviceSealedExecutionState.contains(key)) {
      // These JSON blobs are sealed with SecretVault because an Xtream stream
      // URL can embed the account password. Copying the opaque `enc1:` value
      // would make it unreadable on another installation; copying plaintext
      // would also hand startup an already-resolved source URL and headers.
      // Preserve the ordinary IPTV startup enable/mode preferences, but make
      // the destination resolve its own channel state instead.
      return (include: true, value: null);
    }
    if (key == 'playback_state_v1') {
      return (
        include: true,
        value: value is String ? _portablePlaybackState(value) : null,
      );
    }
    if (key.startsWith('series_source_')) {
      return (
        include: true,
        value: value is String ? _portableSeriesSources(value) : null,
      );
    }
    if (_customPlayerSelections.containsKey(key) && value is String) {
      return _customPlayerSelections[key]!.contains(value)
          ? (include: false, value: null)
          : (include: true, value: value);
    }
    if (key == 'subtitle_selected_font_id' &&
        value is String &&
        value.startsWith('custom_')) {
      return (include: false, value: null);
    }
    return (include: true, value: value);
  }

  /// Resume history is portable, but the resolved source that happened to play
  /// on the source device is not. It may be a local path, an expiring signed
  /// URL, or carry authorization headers. The destination can resolve a fresh
  /// source while retaining title, identity, progress, speed, and completion.
  static String? _portablePlaybackState(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return jsonEncode(_withoutPlaybackExecutionData(decoded));
    } on FormatException {
      return null;
    }
  }

  static Object? _withoutPlaybackExecutionData(Object? value) {
    if (value is List) {
      return <Object?>[
        for (final item in value) _withoutPlaybackExecutionData(item),
      ];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String &&
              !_playbackExecutionFields.contains(
                (entry.key as String).toLowerCase(),
              ))
            entry.key as String: _withoutPlaybackExecutionData(entry.value),
      };
    }
    return value;
  }

  /// Series pins can mix portable cloud/addon sources with absolute local
  /// files. Keep the portable entries and explicitly clear a local-only or
  /// malformed pin on restore.
  static String? _portableSeriesSources(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is List) {
        final portable = <Object?>[];
        for (final item in decoded) {
          if (item is! Map) continue;
          final normalized = _portableSeriesSource(item);
          if (normalized != null) portable.add(normalized);
        }
        return portable.isEmpty ? null : jsonEncode(portable);
      }
      if (decoded is Map) {
        final portable = _portableSeriesSource(decoded);
        return portable == null ? null : jsonEncode(portable);
      }
    } on FormatException {
      // A malformed binding is unusable at the source and may still contain an
      // absolute path. Do not make that path authoritative on another device.
    }
    return null;
  }

  static Map<String, Object?>? _portableSeriesSource(Map source) {
    final service = source['debridService'];
    final hasLocalCapability =
        source['localPath'] != null ||
        source['localUri'] != null ||
        source['filePath'] != null;
    if (service == 'local' ||
        (hasLocalCapability && (service is! String || service.isEmpty))) {
      return null;
    }
    return <String, Object?>{
      for (final entry in source.entries)
        if (entry.key is String && !_localSeriesFields.contains(entry.key))
          entry.key as String: entry.value,
    };
  }

  static const Set<String> _localSeriesFields = <String>{
    'localPath',
    'localUri',
    'localKind',
    'localSizeBytes',
    'localModifiedAt',
    'filePath',
  };

  static const Set<String> _playbackExecutionFields = <String>{
    'url',
    'videourl',
    'streamurl',
    'localpath',
    'localuri',
    'filepath',
    'headers',
    'httpheaders',
  };

  static const Set<String> _deviceSealedExecutionState = <String>{
    'iptv_last_live_channel',
    'startup_iptv_channel',
  };

  /// Compatibility scalars left behind by pre-registry releases. Modern
  /// packages carry the corresponding connection exactly once as an encrypted
  /// resource, so these must not be copied again as profile preferences.
  static const Set<String> _legacyResourceAuthorityKeys = <String>{
    'real_debrid_api_key',
    'torbox_api_key',
    'premiumize_api_key',
    'alldebrid_api_key',
    'mdblist_api_key',
    'mdblist_username',
    'reddit_access_token',
    'reddit_refresh_token',
    'reddit_username',
    'trakt_access_token',
    'trakt_refresh_token',
    'trakt_username',
    'trakt_token_expiry',
    'simkl_access_token',
    'simkl_username',
    'pikpak_email',
    'pikpak_password',
    'pikpak_access_token',
    'pikpak_refresh_token',
    'pikpak_device_id',
    'pikpak_captcha_token',
    'pikpak_user_id',
    'webdav_base_url',
    'webdav_username',
    'webdav_password',
  };

  static const Set<String> _nonPortableKeys = <String>{
    // Registry resources are the sole portable copy of connection material.
    'real_debrid_endpoint',
    'webdav_servers_v1',
    'indexer_manager_configs_v1',
    'iptv_playlists',
    'stremio_addons_v1',

    // Profile readiness is restored from the authenticated profile record.
    'initial_setup_complete_v1',

    // Device capabilities and destinations are invalid without the target
    // installation's OS grant.
    'battery_opt_status_v1',
    'download_tree_uri_v1',
    'download_tree_display_name_v1',
    'download_dir_path_v1',
    'subtitle_custom_fonts',
    'vault_key_source_v1',

    // These values are executed/interpreted as launch templates or absolute
    // executable paths. Trusted built-in player selections remain portable.
    'external_player_custom_path',
    'external_player_custom_name',
    'external_player_custom_command',
    'ios_custom_scheme_template',
    'linux_custom_command',
    'windows_custom_command',
  };

  static const Map<String, Set<String>> _customPlayerSelections =
      <String, Set<String>>{
        'external_player_preferred': <String>{
          'custom',
          'custom_app',
          'custom_command',
        },
        'ios_external_player_preferred': <String>{'custom_scheme'},
        'linux_external_player_preferred': <String>{'custom_command'},
        'windows_external_player_preferred': <String>{'custom_command'},
      };

  static final RegExp _credentialPattern = RegExp(
    r'(api.?key|password|access.?token|refresh.?token|credential|secret)',
    caseSensitive: false,
  );
}
