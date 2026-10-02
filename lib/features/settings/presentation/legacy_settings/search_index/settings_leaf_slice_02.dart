import 'package:debrify/screens/settings/settings_search.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice02 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice2() {
    return [
      // WebDAV — server editor plus the three persistent switches.
      leaf(
        'WebDAV',
        'WebDAV server',
        'Add, edit, test or disconnect a WebDAV server',
        const [
          'add server',
          'another server',
          'server name',
          'server url',
          'seedbox',
          'nas',
          'username',
          'password',
          'app token',
          'save and test',
          'disconnect',
        ],
      ),
      leaf('WebDAV', 'Enable WebDAV', 'Show WebDAV features in the app', const [
        'enable',
        'disable',
        'integration',
        'cloud',
        'server',
      ]),
      leaf(
        'WebDAV',
        'Hide from navigation',
        'Keep WebDAV configured but remove its tab',
        const ['hide', 'navigation', 'nav', 'tab', 'sidebar'],
      ),
      leaf(
        'WebDAV',
        'Show videos only',
        'Hide non-video files while browsing WebDAV',
        const ['video files', 'filter', 'hide files', 'folders'],
      ),

      // Jackett / Prowlarr editor. These controls live one dialog below the
      // manager page, but the manager is the stable deep-link destination.
      leaf(
        'Indexer Managers',
        'Add or edit an indexer manager',
        'Connect a Jackett or Prowlarr server',
        const [
          'add engine',
          'edit engine',
          'type',
          'name',
          'base url',
          'api key',
          'jackett indexer id',
          'prowlarr',
          'torznab',
          'delete engine',
          'remove manager',
        ],
      ),
      leaf(
        'Indexer Managers',
        'Categories',
        'Limit a manager to Torznab category IDs',
        const ['category', 'categories', '2000', '5000', 'movies', 'series'],
      ),
      leaf(
        'Indexer Managers',
        'Max results',
        'Maximum results returned by this manager',
        const ['result limit', '25', '50', '100', '200'],
      ),
      leaf(
        'Indexer Managers',
        'Timeout seconds',
        'How long to wait for Jackett or Prowlarr',
        const ['timeout', 'connection', 'slow', '5', '600'],
      ),
      leaf(
        'Indexer Managers',
        'Enabled',
        'Include or exclude this manager from torrent searches',
        const ['enable', 'disable', 'search source', 'engine'],
      ),
      leaf(
        'Indexer Managers',
        'Test connection',
        'Check that an indexer manager is reachable',
        const ['test', 'network', 'reachable', 'jackett', 'prowlarr'],
      ),
    ];
  }
}
