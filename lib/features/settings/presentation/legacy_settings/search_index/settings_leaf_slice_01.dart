import 'package:debrify/screens/settings/settings_search.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice01 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice1() {
    return [
      // Debrid providers — cache checks, post-torrent action, file handling.
      leaf(
        'Torbox',
        'Check Torbox cache during searches',
        'Verify a cached copy before enabling quick actions',
        const ['cache', 'cached', 'quick action', 'badge', 'instant'],
      ),
      leaf(
        'Torbox',
        'Post-Torrent Action',
        'What happens after adding a torrent to Torbox',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in torbox',
          'add to playlist',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'Torbox',
        'Hide Torbox from Navigation',
        'Hide the Torbox tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'Torbox',
        'Enable Torbox',
        'Turn the Torbox integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'Premiumize',
        'Check Premiumize cache during searches',
        'Show a cached badge on Premiumize results',
        const ['cache', 'cached', 'badge', 'instant'],
      ),
      leaf(
        'Premiumize',
        'Post-Torrent Action',
        'What happens after adding a torrent to Premiumize',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in premiumize',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'Premiumize',
        'Hide Premiumize from Navigation',
        'Hide the Premiumize tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'Premiumize',
        'Enable Premiumize',
        'Turn the Premiumize integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'Real Debrid',
        'File Selection',
        'How files are picked when adding to Real-Debrid',
        const [
          'file selection',
          'smart',
          'largest',
          'video files',
          'all files',
        ],
      ),
      leaf(
        'Real Debrid',
        'Post-Torrent Action',
        'What happens after adding a torrent to Real-Debrid',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in real-debrid',
          'add to playlist',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'Real Debrid',
        'Skip blocked torrents',
        'Skip likely-blocked releases in Quick Play',
        const [
          'content filter',
          'bypass',
          'blocked',
          'web-dl',
          'webrip',
          'hdrip',
        ],
      ),
      leaf(
        'Real Debrid',
        'Hide Real Debrid from Navigation',
        'Hide the Real-Debrid tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'Real Debrid',
        'Enable Real Debrid',
        'Turn the Real-Debrid integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'AllDebrid',
        'Post-Torrent Action',
        'What happens after adding a torrent to AllDebrid',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
        ],
      ),
      leaf(
        'AllDebrid',
        'Hide AllDebrid from Navigation',
        'Hide the AllDebrid tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'AllDebrid',
        'Enable AllDebrid',
        'Turn the AllDebrid integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'PikPak',
        'Show Only Video Files',
        'Filter PikPak folders to video files only',
        const ['video only', 'files', 'folders', 'filter'],
      ),
      leaf(
        'PikPak',
        'Ignore Videos Under 100MB',
        'Hide small video files in PikPak',
        const ['ignore small', '100mb', 'small videos', 'filter'],
      ),
      leaf(
        'PikPak',
        'Post-Torrent Action',
        'What happens after adding a torrent to PikPak',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in pikpak',
          'add to playlist',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'PikPak',
        'Restrict Access to Folder',
        'Limit PikPak access to a single folder',
        const [
          'restrict',
          'folder',
          'access',
          'security',
          'select folder',
          'change folder',
          'remove restriction',
        ],
      ),
      leaf(
        'PikPak',
        'Hide PikPak from Navigation',
        'Hide the PikPak button and tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'PikPak',
        'Enable PikPak Integration',
        'Turn the PikPak integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      // Lives in the logged-OUT login form (pikpak_settings_page: the
      // `if (!_isConnected)` block), so the subtitle says where to find it
      // rather than promising a row a connected user won't see.
      leaf(
        'PikPak',
        'Reset Device ID',
        'On the PikPak login screen — issue a fresh device ID if sign-in fails',
        const ['device id', 'reset', 'login problem', 'captcha', 'sign in'],
      ),
    ];
  }
}
