import 'package:debrify/screens/settings/settings_search.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice04 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice4() {
    return [
      // Home Page
      leaf(
        'Home Screen',
        'Home Rows',
        'Choose which rows appear on Home',
        const [
          'home rows',
          'rows',
          'catalogs',
          'customize',
          'show',
          'hide',
          'arrange',
          'reorder',
          'all on',
          'all off',
          'invert',
          'continue watching',
          'trakt',
          'simkl',
          'mdblist',
          'iptv lists',
          'watchlist',
          'favorites',
          'favourites',
        ],
      ),
      leaf(
        'Home Screen',
        'Hero Source',
        'Choose which catalogs feed the Spotlight hero',
        const [
          'spotlight',
          'hero',
          'first row',
          'surprise me',
          'random',
          'my picks',
          'custom',
          'catalog',
          'reel',
        ],
      ),
      leaf(
        'Home Screen',
        'Landscape Cards',
        'Use wide 16:9 artwork instead of portrait posters',
        const [
          'landscape',
          'wide',
          '16:9',
          'poster',
          'portrait',
          'card orientation',
          'artwork',
        ],
      ),
      leaf(
        'Home Screen',
        'Continue Watching',
        'Show recently watched on Home',
        const ['continue watching', 'recently watched', 'history'],
      ),
      leaf(
        'Home Screen',
        'Hold to Quick Play',
        'Play immediately when holding a Continue Watching card',
        const [
          'hold',
          'long press',
          'quick play',
          'continue watching',
          'card action',
        ],
      ),
      leaf(
        'Home Screen',
        'Hide Provider Cards',
        'Hide debrid status cards on Home',
        const ['hide', 'provider cards', 'debrid', 'status'],
      ),
      leaf(
        'Home Screen',
        'Hide Titles and Ratings',
        'Remove title and rating text from Home cards',
        const ['hide', 'titles', 'ratings', 'cards', 'clean artwork'],
      ),
      leaf(
        'Tracking',
        'Hide watched titles',
        'Remove finished movies and shows from Home, Search and Discover',
        const [
          'hide',
          'watched',
          'seen',
          'finished',
          'completed',
          'already watched',
          'filter',
        ],
      ),
      leaf(
        'Home Screen',
        'Hide Catalog Add-on Names',
        'Remove source labels beside Home row headings',
        const [
          'hide',
          'catalog',
          'addon',
          'add-on',
          'source label',
          'row heading',
          'home cards',
        ],
      ),
      // Not on TV: TV has separate Home and Search tabs, so the page hides the
      // selector there (home_page_settings_page's !isTelevision block).
      if (!deps.isTelevision())
        leaf(
          'Home Screen',
          'Default view',
          'Which view Home opens on (Catalog or Keyword)',
          const [
            'default view',
            'catalog',
            'keyword',
            'landing',
            'opens on',
            'startup',
          ],
        ),
      // Both ambient-trailer surfaces now exist on every platform.
      leaf(
        'Home Screen',
        'Trailer on Home Spotlight',
        'Play a trailer in the Home and Discover hero',
        const ['trailer', 'spotlight', 'hero', 'ambient', 'autoplay'],
      ),
      leaf(
        'Home Screen',
        'Trailer on Detail Page',
        'Play a trailer behind the movie/series detail page',
        const ['trailer', 'detail page', 'preview', 'backdrop', 'autoplay'],
      ),
      leaf(
        'Home Screen',
        'Trailer Sound',
        'Play ambient Home and detail-page trailers with audio',
        const ['trailer', 'sound', 'audio', 'mute', 'silent', 'ambient'],
      ),
      leaf(
        'Home Screen',
        'Trailer volume',
        'Set the volume used by ambient trailers',
        const ['trailer', 'volume', 'sound', 'audio', 'percent', 'ambient'],
      ),
      // TV only: the native hardware-plane renderer for those trailers.
      if (deps.isTelevision())
        leaf(
          'Home Screen',
          'Native Trailer Surface',
          'Render trailers on a hardware surface for smoother playback',
          const [
            'native',
            'surface',
            'hardware',
            'smooth',
            'stutter',
            'glitch',
            'performance',
            'trailer',
          ],
        ),
    ];
  }
}
