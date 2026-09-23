# Jellyfin and Emby sources

Open **Settings → Jellyfin & Emby → Connect server**. Choose the server type,
enter its URL (including a reverse-proxy base path, if any), and sign in with
a server user that can play the desired library. Multiple servers are supported.
Use **Test connection**, **Reconnect**, or **Disconnect** on an existing connection.

Open a movie or an individual episode and select **Sources**. Matching versions
appear under the server's display name, with resolution/container/codec labels.
They also participate in Quick Play when direct links and addon sources are
allowed, and can be ordered in source priority settings.
Debrify TV's automatic channel playback currently excludes native media-server
sources because its channel-switching path cannot carry authentication headers.

Matching uses exact IMDb, TMDB, or TVDB IDs, verifies the returned item type,
and requires exact season/episode numbers for series, including season zero.
No title-only guesses are made. Anime libraries using different numbering or
catalog IDs need compatible server metadata before they will match. A
whole-season/series pack search does not return individual server episodes.
Audio-language filters use the available embedded audio tracks, not subtitle
languages or guesses from the library title. Unknown languages are not assumed
to be English.

Playback streams the original file through the server to Debrify. It does not
hand authenticated streams to external players or DeoVR; these streams always
use the internal player. It does not
open the server's filesystem path on the client. The device must support the
file's formats and have enough bandwidth; transcoding/remux negotiation and
external server subtitle fetching are not implemented. Embedded audio/subtitle
tracks and Debrify's existing progress
and subtitle features continue to use the normal player.
Downloading Jellyfin/Emby sources to the device is currently disabled; the
background downloader does not yet support their authenticated stream lifecycle.

Pinned movies retain their selected server version. Pinned series retain the
server and selected resolution for subsequent episodes. Pins contain opaque
IDs, not server URLs or tokens, and resolve current credentials when replayed.
If a pinned version is gone, normal source-search fallback applies.

Connections use the existing encrypted profile resource registry and follow
its default sharing rules. Passwords are used only during login; tokens remain
in the encrypted registry. Existing search results are rejected after a profile
switch, credential change, disabled connection, or grant revocation. Disconnecting
an owned shared connection requires confirming its impact on other profiles.
Legacy installs without a committed profile cannot add media servers.

## Watch-state sync

Enable **Settings → Jellyfin & Emby → Sync server watch progress** for the
current Debrify profile. It is off by default. Shared connections use the same
server account: enabling this also updates that account's progress in other apps.

For a selected server movie or episode, Debrify reads that user's resume and
watched state before opening playback. Server progress seeds the local bookmark
when none exists, or replaces it when the server supplies a newer timestamp.
Unknown timestamps do not replace existing bookmarks, and local completed marks
are retained. A server's `Played` history flag does not discard an active partial
rewatch bookmark. Existing tracker-progress selection, explicit resume, start-over,
random-start and episode auto-advance rules still apply; server imports feed the
local resume source, not a new tracker priority.

Validated internal playback reports start, progress (about every ten seconds,
plus pause/seek changes), and stop to the selected server. Completion reports
watched status immediately at EOF, even while the player stays open. Replaying
the same open item starts a fresh watch session without importing an old bookmark.
Failed/unplayed candidates never report playback. Source switches
and episode changes keep separate item/session identities. Disconnecting,
revoking a connection, switching profiles or turning sync off prevents subsequent
reports. Enable the setting before launching a new playback session.

This is playback-driven sync, not a background library mirror: other apps'
changes are read the next time a server item is opened. Playing through debrid
or another addon does not update a server. Manual watched/unwatched edits outside
playback are not broadcast, and server unwatched state does not erase local
completion. Network failures do not block playback; there is no offline replay
queue. If the initial watch-state read fails, that playback attempt does not
write progress back to the server.

## Discover browsing

Choose **Jellyfin** or **Emby** in Discover's Source selector, then select a
connected server and video library. Both can also be saved as the default
Discover source in Settings. Browse folders, series, seasons and episodes, or
search within the current library/folder. Results are paged; library browsing
supports name, date-added and year sorting. Recently Added and Continue Watching
use the server's own library data and ordering.

Opening a video displays its server description and available original-file
versions. Playback opens that exact server item in the internal player, without
requiring an IMDb/TMDB match. This includes video recordings indexed in a server
library; live-TV/channel browsing is not included. Artwork is fetched with
authentication headers, without credentials in URLs.

Server-library progress is kept separate from same-name catalog titles and other
server accounts. These items do not enter the catalog Home Continue Watching
row; reopen them from Discover. Enable the existing media-server watch-sync
option to publish playback progress to the server's Continue Watching view.
Transcoding, external-player handoff and automatic next-episode playback from
this browser are not included. Episodes can be selected through season browsing.

## Discover validation

Tests cover authenticated browsing/artwork, paging, recordings without catalog
IDs, revoked access, isolated bookmarks, stale responses, phone layout and TV
select navigation. The opt-in live suite also covers real Jellyfin/Emby library
hierarchies, search, recent/resumable queries and exact-item source resolution.

## Existing playback validation

Automated tests use simulated Jellyfin/Emby responses for login, reverse-proxy
paths, redirects, timeouts, exact matching, paging, versions, next-episode pin
resolution, permissions, profile changes and source-search integration.
Watch-sync tests cover user-specific progress, tick conversion, authenticated
empty-body check-ins, throttling/coalescing, ordering, conflict handling,
per-profile opt-in and authorization changes.

The opt-in `test/media_server_live_test.dart` suite exercises actual HTTP calls
and Debrify's source/watch services against isolated synthetic test libraries.
On September 22, 2026 it passed against Jellyfin 12.1.0 and Emby 4.9.3.0:
ordinary-user login, exact movie/episode matching, authenticated byte-range
streaming, pin resolution, resume import, pause/stop, EOF completion, fresh replay
sessions and disconnect protection. Authentication includes the token in the
standard Authorization parameter (required by Jellyfin 12), with the legacy
token header retained for older servers. A separate isolated macOS harness also
verified actual internal-player movie playback from both servers, server resume,
pause persistence, switching Emby to Jellyfin, seeking, EOF reporting while the
route stays open, replay progress, and an episode transition from Jellyfin S01E01
to Emby S01E02 with separate outgoing/incoming bookmarks. The harness used
in-memory preferences and a temporary profile, not personal application data.

Run with:

```sh
DEBRIFY_MEDIA_SERVER_LIVE=1 flutter test --no-pub test/media_server_live_test.dart
```

Tests are skipped by default and require
servers named `Debrify Test Jellyfin` / `Debrify Test Emby`, ordinary user
`debrify-test`, and the documented synthetic titles/catalog IDs. URLs may be
overridden using `DEBRIFY_JELLYFIN_URL` / `DEBRIFY_EMBY_URL`; passwords come from
matching `DEBRIFY_*_PASSWORD` environment variables or macOS Keychain services
`Debrify Test Jellyfin` / `Debrify Test Emby`, account `debrify-test`. Tests change
only synthetic watch data and restore the movie/first episode bookmark to 04:00.

Before release, check against real Jellyfin and Emby servers on supported
devices: login, movie playback and seeking, multiple versions, episode advance,
embedded subtitles/audio, source switching, expired token/reconnect, and a
remote server with a reverse-proxy base path. With watch sync enabled, also check
resume from another client, pause/exit, completion, episode/source switching,
and profile/account changes during playback. Real-server API verification does
not substitute for playback checks across all supported device platforms.
