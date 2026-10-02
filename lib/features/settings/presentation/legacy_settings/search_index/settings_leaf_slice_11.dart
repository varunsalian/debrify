import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice11 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice11() {
    return [
      // Trackers — the pages behind the connection cards.
      leaf(
        'Tracking',
        'Scrobble',
        'Choose which connected services record playback',
        const [
          'sync',
          'catalog',
          'watchlist',
          'collection',
          'history',
          'scrobble',
          'refresh',
        ],
      ),
      leaf(
        'Tracking',
        'Progress source',
        'Choose resume, progress bar and Continue Watching ownership',
        const [
          'sync',
          'catalog',
          'watchlist',
          'plan to watch',
          'history',
          'scrobble',
          'refresh',
        ],
      ),
      leaf(
        'Tracking',
        'Watched ticks',
        'Choose which histories draw watched ticks on posters',
        const ['watched', 'checkmark', 'tick', 'local', 'trakt', 'simkl'],
      ),
      if (kMdblistEnabled)
        leaf(
          'MDBList',
          'MDBList API Key',
          'Connect MDBList and browse your lists',
          const [
            'api key',
            'add api key',
            'logout',
            'lists',
            'liked',
            'supporter',
            'usage',
            'mdblist preferences',
            'open mdblist.com/preferences',
          ],
        ),

      // Remote
      leaf(
        'Remote',
        'Control another device',
        'Use this device as a remote, or send your setup to another',
        const [
          'remote',
          'control',
          'pair',
          'wifi',
          'send setup',
          'push addons',
          'handoff',
          'd-pad',
          'paired remote devices',
          'manage pairing',
        ],
      ),
      leaf(
        'Remote',
        'Receive from another device',
        'Let another device control this one or send it addons & channels',
        const [
          'receive',
          'target',
          'pair',
          'import setup',
          'addons',
          'channels',
          'sessions',
          'paired remote devices',
          'manage pairing',
        ],
      ),
    ];
  }
}
