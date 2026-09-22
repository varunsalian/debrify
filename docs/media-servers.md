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
file's formats and have enough bandwidth; transcoding/remux negotiation,
external server subtitle fetching, and two-way server watch-state sync are not
implemented. Embedded audio/subtitle tracks and Debrify's existing progress
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

## Validation

Automated tests use simulated Jellyfin/Emby responses for login, reverse-proxy
paths, redirects, timeouts, exact matching, paging, versions, next-episode pin
resolution, permissions, profile changes and source-search integration.

Before release, check against real Jellyfin and Emby servers on supported
devices: login, movie playback and seeking, multiple versions, episode advance,
embedded subtitles/audio, source switching, expired token/reconnect, and a
remote server with a reverse-proxy base path. No real server was available
during this implementation, so real-server playback is not yet verified.
