import 'package:debrify/screens/settings/settings_search.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice08 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice8() {
    return [
      // Debrify TV
      leaf(
        'Debrify TV',
        'Keyword Threshold',
        'Choose when Debrify TV fetches more or fewer results per keyword',
        const ['keyword', 'threshold', 'results', 'fetch', 'global tv mode'],
      ),
      leaf(
        'Debrify TV',
        'Batch Size',
        'Number of keywords processed in each batch',
        const ['batch', 'keywords', 'performance', 'global tv mode'],
      ),
      leaf(
        'Debrify TV',
        'Min Torrents Per Keyword',
        'Skip keywords with fewer torrent results',
        const ['minimum', 'torrents', 'keyword', 'skip', 'result count'],
      ),
      leaf(
        'Debrify TV',
        'Max Keywords (Quick Play)',
        'Limit the keywords used in Quick Play mode',
        const ['maximum', 'keyword limit', 'quick play', 'performance'],
      ),
      leaf(
        'Debrify TV',
        'Avoid NSFW Content',
        'Filter adult content out of Debrify TV results',
        const ['nsfw', 'adult', 'safe', 'filter', 'content'],
      ),
      leaf(
        'Debrify TV',
        'Prepare Torrents in Background',
        'Pre-add upcoming Real-Debrid and AllDebrid torrents',
        const [
          'background',
          'prefetch',
          'pre-fetch',
          'prepare',
          'faster playback',
          'real-debrid',
          'alldebrid',
        ],
      ),
      leaf(
        'Debrify TV',
        'Engine TV Mode',
        'Enable or disable each search engine for Debrify TV',
        const ['engine', 'tv mode enabled', 'tv mode disabled', 'toggle'],
      ),
      leaf(
        'Debrify TV',
        'Small Channel Limit',
        'Maximum results for each engine in small channel mode',
        const ['small channel', 'result limit', 'max results', 'engine'],
      ),
      leaf(
        'Debrify TV',
        'Large Channel Limit',
        'Maximum results for each engine in large channel mode',
        const ['large channel', 'result limit', 'max results', 'engine'],
      ),
      leaf(
        'Debrify TV',
        'Quick Play Limit',
        'Maximum results for each engine in Quick Play mode',
        const ['quick play', 'result limit', 'max results', 'engine'],
      ),
      leaf(
        'Debrify TV',
        'Reset to Defaults',
        'Restore the default Debrify TV engine settings',
        const ['reset', 'defaults', 'restore', 'engines'],
      ),

      // Stremio TV
      leaf(
        'Stremio TV',
        'Rotation Interval',
        'How often the now-playing item changes on movie channels',
        const ['rotation', 'interval', 'minutes', 'movie', 'change', 'shuffle'],
      ),
      leaf(
        'Stremio TV',
        'Series Rotation Interval',
        'How often the episode changes on series channels',
        const [
          'series',
          'episode',
          'rotation',
          'interval',
          'minutes',
          'change',
          'schedule',
        ],
      ),
      leaf(
        'Stremio TV',
        'Preferred Quality',
        'Prioritize streams matching this quality',
        const ['quality', '4k', '2160p', '1080p', '720p', 'resolution'],
      ),
      leaf(
        'Stremio TV',
        'Debrid Provider',
        'Which provider resolves Stremio TV torrent streams',
        const ['debrid', 'provider', 'auto', 'real-debrid', 'torbox', 'pikpak'],
      ),
      leaf(
        'Stremio TV',
        'Try torrents first',
        'Resolve torrents via debrid before trying direct streams',
        const ['torrents first', 'direct', 'stream', 'order', 'fallback'],
      ),
      leaf(
        'Stremio TV',
        'Random Episodes',
        'Pick episodes at random on series channels',
        const ['random', 'shuffle', 'episodes', 'series'],
      ),
      leaf(
        'Stremio TV',
        'Start Position',
        'Where playback begins within the current slot',
        const ['start', 'position', 'beginning', 'slot progress', 'resume'],
      ),
      leaf(
        'Stremio TV',
        'Hide Currently Playing',
        'Blur the poster and hide details for a surprise',
        const ['hide', 'spoiler', 'surprise', 'blur', 'now playing'],
      ),
      leaf(
        'Stremio TV',
        'Auto-refresh',
        'Refresh Stremio TV channels automatically',
        const ['auto refresh', 'refresh', 'update', 'channels'],
      ),
    ];
  }
}
