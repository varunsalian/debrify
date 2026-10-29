// Presentation bridge between IPTV and the Sports board: wires the
// profile-scoped follow store and the SQLite guide search into the board's
// providers, turns a chosen channel back into an IPTV channel to play, and
// opens the Sports & leagues picker for IPTV settings.

import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/iptv_sports_guide_playlists.dart';
import 'package:debrify/features/sports/data/shared_prefs_sports_prefs.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/data/sqlite_sports_guide_source.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_board_view.dart';
import 'package:debrify/features/sports/presentation/sports_league_sheet.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _followStore = SportsFollowStore(
  () async => SharedPrefsSportsPrefs(await ProfilePreferences.instance()),
);

final _guideSource = SqliteSportsGuideSource(
  dbPath: () => IptvCatalogDb.path,
  playlists: loadIptvSportsGuidePlaylists,
);

/// The Sports view shown when the IPTV "Sports" shelf is selected.
class SportsIptvBoard extends StatelessWidget {
  const SportsIptvBoard({super.key, required this.onPlay});

  /// Plays a live channel through the IPTV screen's normal playback path.
  final Future<void> Function(IptvChannel channel) onPlay;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        sportsFollowStoreProvider.overrideWithValue(_followStore),
        sportsGuideSourceProvider.overrideWithValue(_guideSource),
      ],
      child: SportsBoardView(onPlay: (ref) => onPlay(sportsChannelToIptv(ref))),
    );
  }
}

/// The Sports & leagues picker, as IPTV settings opens it: the same sheet as
/// the board's filter button, over the app-wide league choices.
Future<void> showIptvSportsLeagues(BuildContext context) =>
    showSportsLeagueSheet(context);

/// A matched guide channel as the IPTV player expects it (always live). The
/// originating playlist rides along in the same attribute saved lists use
/// (`IptvMembershipState.kListOriginAttribute`), so playback resolves that
/// provider's credentials rather than the selected shelf's.
IptvChannel sportsChannelToIptv(SportsChannelRef ref) => IptvChannel(
  name: ref.name,
  url: ref.url,
  logoUrl: ref.logoUrl,
  group: ref.group,
  contentType: 'live',
  attributes: {
    ...ref.attributes,
    if (ref.playlistId != null) 'list_playlist_id': ref.playlistId!,
  },
  httpHeaders: ref.httpHeaders,
);
