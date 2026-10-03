import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/material.dart';

typedef IptvGuideContextDeps = ({
  IptvCatalogState catalogState,
  IptvSettingsState settingsState,
  IptvStatusState statusState,
  BuildContext Function() context,
  void Function(ChipOwner owner) hideChipIfOwned,
  bool Function() mounted,
  void Function(int ticket, int? bytes, int? totalBytes) onGuidePhase,
  StateSetter setState,
});

// ── Spotlight Guide ───────────────────────────────────────────────────────
class IptvGuideContext {
  final IptvGuideContextDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvSettingsState _settingsState;
  final IptvStatusState _statusState;

  IptvGuideContext(this._deps)
    : _catalogState = _deps.catalogState,
      _settingsState = _deps.settingsState,
      _statusState = _deps.statusState;

  /// Activate (or clear) XMLTV guide data for the loaded playlist. Fire and
  /// forget: the list renders immediately, and rows re-render with their
  /// schedule affordances if/when the guide lands.
  ///
  /// Guide URL resolution, per playlist kind:
  /// - Plain M3U: user-configured epgUrl > the header's url-tvg > (when the
  ///   playlist is really an Xtream `get.php` export, i.e. its channel URLs
  ///   carry credentials) the panel's own xmltv.php.
  /// - Xtream (live view): user-configured epgUrl > the panel's xmltv.php.
  ///   This layers ON TOP of the per-stream get_short_epg endpoints — the
  ///   XMLTV index answers first, the endpoints cover anything it doesn't.
  ///   It's the same source TiviMate reads, so panels whose per-stream EPG
  ///   is broken/disabled (a real-world regular) still get a full guide.
  /// - Favorites/custom lists: one guide context per originating provider.
  /// - Everything else (Stremio/continue): no guide context.
  void updateEpgContext(
    IptvPlaylist playlist,
    IptvParseResult result,
    int ticket, {
    // Suppress the user-facing failure hints (background revalidate re-runs
    // already had them surfaced by the foreground pass this visit).
    bool quiet = false,
  }) {
    final service = IptvEpgService.instance;
    _statusState.lastGuideMb = -1;
    if (playlist.isFavorites || playlist.isCustomList) {
      _deps.hideChipIfOwned(ChipOwner.guide);
      unawaited(
        Zone.root.run(
          () => service.setListEpgContext(
            channels: result.channels,
            playlists: _settingsState.playlists,
            isCurrent: () =>
                _deps.mounted() && ticket == _catalogState.loadTicket,
          ),
        ),
      );
      return;
    }
    final isPlainM3u = !playlist.isVirtual && !playlist.isXtreamCodes;
    final isXtreamLive =
        playlist.isXtreamCodes && _catalogState.selectedContentType == 'live';
    if (!isPlainM3u && !isXtreamLive) {
      service.clearM3uEpgContext();
      _deps.hideChipIfOwned(ChipOwner.guide);
      return;
    }
    // A user-configured guide URL beats every derived source.
    final manual = playlist.epgUrl?.trim();
    final hasManualUrl = manual != null && manual.isNotEmpty;
    String? epgUrl;
    if (hasManualUrl) {
      epgUrl = manual;
    } else if (isXtreamLive) {
      epgUrl = IptvEpgService.xmltvUrlFor(
        playlist.serverUrl!,
        playlist.username ?? '',
        playlist.password ?? '',
      );
    } else {
      epgUrl = result.epgUrl;
      if (epgUrl == null || epgUrl.trim().isEmpty) {
        // No configured or declared guide — an Xtream-export M3U can still
        // derive the panel's own xmltv.php from any channel's stream URL.
        // Such exports are homogeneous (every URL carries the credentials),
        // so a bounded sample decides. Bounding matters: the
        // channels list is a paging facade, and walking all of it here would
        // synchronously materialize the whole catalog on the UI isolate for
        // a plain M3U that derives nothing.
        final channels = result.channels;
        final Iterable<IptvChannel> probe = channels is DbChannelList
            ? channels.effectiveSnapshot.page(offset: 0, limit: 50, live: true)
            : channels;
        for (final channel in probe) {
          if (!channel.isLive) continue;
          final derived = IptvEpgService.xmltvUrlForChannelUrl(channel.url);
          if (derived != null) {
            epgUrl = derived;
            break;
          }
        }
      }
    }
    // Started in the ROOT zone on purpose. This is fire-and-forget work that
    // takes the maintenance gate for its catalog scan and guide ingest, and
    // one of its callers (the background refresh) is itself running inside
    // that gate — inheriting the caller's zone would make the gate re-entrant
    // for this long-lived job and let it run alongside the next queued one,
    // which is the overlap being designed out.
    Zone.root
        .run(
          () => service.setM3uEpgContext(
            playlistKey: playlist.id,
            epgUrl: epgUrl,
            channels: result.channels,
            // DB-backed view: the guide stores its rows in iptv_catalog.db and
            // binds URLs through the catalog instead of whole-playlist maps.
            dbCatalogKey: _catalogState.dbSnapshot?.catalogKey,
            onPhase: (phase, {bytes, totalBytes}) =>
                _deps.onGuidePhase(ticket, bytes, totalBytes),
          ),
        )
        .then((status) {
          // The guide is done one way or another — drop its chip if it is
          // still the one speaking.
          _deps.hideChipIfOwned(ChipOwner.guide);
          if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
          // Failure hints only for a guide the user configured themselves.
          // Header-derived url-tvg URLs are routinely dead in wild playlists —
          // those users never asked for EPG and got silent no-guide before;
          // nagging them on every load would be a regression.
          void hint(String message) {
            if (quiet || !hasManualUrl) return;
            ScaffoldMessenger.of(
              _deps.context(),
            ).showSnackBar(SnackBar(content: Text(message)));
          }

          switch (status) {
            case M3uEpgStatus.matched:
              // Capability changed: rebuild the rows so EPG-covered channels
              // gain the RIGHT-key/calendar affordance. The rail card refreshes
              // itself via the service's contextVersion listener.
              _deps.setState(() {});
            // The guide failing is otherwise invisible — rows just never grow
            // their affordances — and "EPG doesn't work" reports can't tell
            // the flavors apart. Say which one happened.
            case M3uEpgStatus.noMatch:
              hint(
                'TV guide loaded, but none of its channels matched this '
                'playlist (the ids and names don\'t line up).',
              );
            case M3uEpgStatus.noProgrammes:
              hint(
                'TV guide matched this playlist, but it has no programme '
                'data for the current period.',
              );
            case M3uEpgStatus.failed:
              hint('Couldn\'t load the TV guide — check the EPG URL.');
            case M3uEpgStatus.inactive:
              break;
          }
        })
        // The chain above had NO error handler: a throw anywhere in the
        // guide pipeline (isolate spawn under memory pressure, malformed
        // XMLTV, a BUSY SqliteException from a colliding write) became an
        // unhandled async rejection — and because the work deliberately runs
        // in the root zone, no caller-side guard could ever catch it either.
        // A failed guide load degrades to "no guide", exactly like the
        // status-carrying failures above.
        .catchError((Object e) {
          debugPrint('IPTV: guide context update failed: $e');
          _deps.hideChipIfOwned(ChipOwner.guide);
          if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
          if (!quiet && hasManualUrl) {
            ScaffoldMessenger.of(_deps.context()).showSnackBar(
              const SnackBar(
                content: Text(
                  'Couldn\'t load the TV guide — check the EPG URL.',
                ),
              ),
            );
          }
        });
  }
}
