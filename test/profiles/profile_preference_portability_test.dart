import 'dart:convert';

import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portable URLs and passive platform settings are retained', () {
    for (final key in const <String>{
      'home_default_addon_url',
      'stremio_tv_catalog_repo_urls_v1',
      'android_video_renderer_mode',
      'tvos_force_software_decode',
      'linux_external_player_preferred',
      'windows_external_player_preferred',
      'tv_ui_scale_percent',
    }) {
      expect(ProfilePreferencePortability.allowsKey(key), isTrue, reason: key);
    }
  });

  test('MDBList checkpoint remains portable for explicit backup restore', () {
    const key = 'mdblist_sync_checkpoint_v1';
    const value = '{"server_time":20}';

    expect(ProfilePreferencePortability.allowsKey(key), isTrue);
    expect(ProfilePreferencePortability.prepareValue(key, value), (
      include: true,
      value: value,
    ));
  });

  test('credentials, device grants, and executable templates are rejected', () {
    for (final key in const <String>{
      'provider_api_key',
      'reddit_access_token',
      'reddit_username',
      'trakt_token_expiry',
      'pikpak_device_id',
      'pikpak_user_id',
      'webdav_base_url',
      'webdav_username',
      'remote_paired_devices_v1',
      'download_tree_uri_v1',
      'download_tree_display_name_v1',
      'download_dir_path_v1',
      'external_player_custom_path',
      'external_player_custom_name',
      'external_player_custom_command',
      'ios_custom_scheme_template',
      'linux_custom_command',
      'windows_custom_command',
      'subtitle_custom_fonts',
    }) {
      expect(ProfilePreferencePortability.allowsKey(key), isFalse, reason: key);
    }
  });

  test(
    'credential-shaped engine settings require a secret-inclusive package',
    () {
      const engineKey = 'engine_custom_indexer_api_key';
      expect(ProfilePreferencePortability.allowsKey(engineKey), isFalse);
      expect(
        ProfilePreferencePortability.allowsKey(
          engineKey,
          includeCredentialEngineSettings: true,
        ),
        isTrue,
      );
      expect(
        ProfilePreferencePortability.prepareValue(
          engineKey,
          'engine-owned-secret',
          includeCredentialEngineSettings: true,
        ),
        (include: true, value: 'engine-owned-secret'),
      );
      expect(
        ProfilePreferencePortability.allowsKey(
          'provider_api_key',
          includeCredentialEngineSettings: true,
        ),
        isFalse,
      );
    },
  );

  test('every registered device preference stays outside profile backups', () {
    for (final key in DevicePreferences.allowedKeys) {
      expect(ProfilePreferencePortability.allowsKey(key), isFalse, reason: key);
    }
    expect(
      ProfilePreferencePortability.allowsKey('vault_key_source_v1'),
      isFalse,
    );
  });

  test(
    'custom capability selections do not become active without capability',
    () {
      for (final entry in const <String, String>{
        'external_player_preferred': 'custom_app',
        'ios_external_player_preferred': 'custom_scheme',
        'linux_external_player_preferred': 'custom_command',
        'windows_external_player_preferred': 'custom_command',
        'subtitle_selected_font_id': 'custom_1720000000000',
      }.entries) {
        expect(
          ProfilePreferencePortability.prepareValue(
            entry.key,
            entry.value,
          ).include,
          isFalse,
          reason: entry.key,
        );
      }

      expect(
        ProfilePreferencePortability.prepareValue(
          'linux_external_player_preferred',
          'vlc',
        ),
        (include: true, value: 'vlc'),
      );
      expect(
        ProfilePreferencePortability.prepareValue(
          'subtitle_selected_font_id',
          'notosans',
        ),
        (include: true, value: 'notosans'),
      );
    },
  );

  test('mixed series pins retain cloud sources and remove local paths', () {
    final prepared = ProfilePreferencePortability.prepareValue(
      'series_source_tt1234567',
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'torrentHash': 'portable-hash',
          'debridService': 'rd',
          'debridTorrentId': 'cloud-id',
          // A stale local hint is not authority for this cloud binding. Strip
          // the hint without losing the valid provider source itself.
          'localPath': '/Users/source/stale-cloud-hint',
        },
        <String, Object?>{
          'torrentHash': 'local-hash',
          'debridService': 'local',
          'debridTorrentId': '/Users/source/Videos/show',
          'localPath': '/Users/source/Videos/show',
          'localUri': 'file:///Users/source/Videos/show',
        },
      ]),
    );

    expect(prepared.include, isTrue);
    final restored = jsonDecode(prepared.value! as String) as List;
    expect(restored, hasLength(1));
    expect(restored.single['torrentHash'], 'portable-hash');
    expect(restored.single, isNot(contains('localPath')));
    expect(jsonEncode(restored), isNot(contains('/Users/source')));
  });

  test('local-only, malformed, or wrongly typed series pins clear safely', () {
    for (final value in <Object?>[
      jsonEncode(<String, Object?>{
        'debridService': 'local',
        'localPath': '/mnt/media/show',
      }),
      '{malformed',
      <String>['/mnt/media/show'],
    ]) {
      expect(
        ProfilePreferencePortability.prepareValue(
          'series_source_tt7654321',
          value,
        ),
        (include: true, value: null),
      );
    }
  });

  test(
    'playback progress remains while resolved execution data is removed',
    () {
      final prepared = ProfilePreferencePortability.prepareValue(
        'playback_state_v1',
        jsonEncode(<String, Object?>{
          'video_movie': <String, Object?>{
            'type': 'video',
            'title': 'Movie',
            'url': 'https://signed.example/video?token=secret',
            'positionMs': 12000,
            'durationMs': 90000,
            'httpHeaders': <String, String>{'Authorization': 'Bearer secret'},
            'nested': <String, Object?>{
              'localPath': '/Users/source/movie.mkv',
              'speed': 1.25,
            },
          },
        }),
      );

      expect(prepared.include, isTrue);
      final restored = jsonDecode(prepared.value! as String) as Map;
      final movie = restored['video_movie'] as Map;
      expect(movie['title'], 'Movie');
      expect(movie['positionMs'], 12000);
      expect(movie['durationMs'], 90000);
      expect(movie, isNot(contains('url')));
      expect(movie, isNot(contains('httpHeaders')));
      expect(movie['nested'], <String, Object?>{'speed': 1.25});
      expect(jsonEncode(restored), isNot(contains('secret')));
      expect(jsonEncode(restored), isNot(contains('/Users/source')));
    },
  );

  test('malformed or wrongly typed playback state clears safely', () {
    for (final value in <Object?>[
      '{malformed',
      <String>['not-a-map'],
    ]) {
      expect(
        ProfilePreferencePortability.prepareValue('playback_state_v1', value),
        (include: true, value: null),
      );
    }
  });

  test('device-sealed IPTV execution state clears on export and import', () {
    for (final key in const <String>{
      'iptv_last_live_channel',
      'startup_iptv_channel',
    }) {
      expect(ProfilePreferencePortability.allowsKey(key), isTrue, reason: key);
      expect(
        ProfilePreferencePortability.prepareValue(
          key,
          'enc1:source-device-ciphertext',
        ),
        (include: true, value: null),
        reason: key,
      );
      expect(
        ProfilePreferencePortability.prepareValue(
          key,
          jsonEncode(<String, Object?>{
            'url': 'https://provider.example/live/user/password/1.ts',
            'httpHeaders': <String, String>{'Authorization': 'Bearer secret'},
          }),
        ),
        (include: true, value: null),
        reason: key,
      );
    }
  });
}
