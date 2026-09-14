# Trakt Continue Watching

The episode feed combines Trakt Up Next with saved episode playback. Up Next
alone cannot represent a newly started show with no completed episode.

The latest dated, partial checkpoint wins over older show-level watched activity
and Up Next activity. Otherwise Up Next retains its episode. This deliberately
uses the latest activity for the show rather than resurrecting an older paused
episode after the viewer has completed another episode. A checkpoint newer than
watched history can represent a rewatch, including a fully watched show.
Equal-time playback may enrich the exact Up Next episode, but cannot replace it
with a different episode or override newer watched history.

The merge resolves Trakt, IMDb, and TMDB aliases, emits one card per show, orders
cards by activity, and retains playback deletion IDs. Hidden progress shows,
hidden seasons, and dropped shows remain excluded.

When playback exists, the loader also reads paginated hidden progress, dropped
shows, and show-level watched history. History explicitly requests
`extended=noseasons`: legacy responses without pagination headers are read once,
while responses with explicit page counts are read through their final page.
No speculative history page is requested. It does not request season-by-season
watched progress. These reads add network work; any failed required read returns null so
existing UI snapshots survive. Successful empty playback needs only the existing
Up Next and playback requests.

Malformed records with a usable show identity are isolated conservatively: an
invalid hidden season suppresses that show, and an invalid watched date prevents
that show's checkpoints from overriding Up Next. Unrelated titles still refresh.
Records without a usable identity retain the previous snapshot because their
visibility/history impact cannot be safely assigned to a show. Diagnostic counts
record recovery without storing content identities.

Diagnostic exports include scrobble action, HTTP status, progress, and whether
the request targeted an episode. Merge counts and read-failure stages help
distinguish sending failures from display failures. Titles, content IDs, URLs,
and credentials are not included.

Tests cover new watches, rewatches, stale checkpoints, conflicting episodes,
identity aliases, visibility, ordering, malformed input, and read failures in
`test/trakt_continue_watching_merge_test.dart`.

API references:

- https://github.com/trakt/trakt-api/blob/master/projects/api/src/contracts/scrobble/index.ts
- https://github.com/trakt/trakt-api/blob/master/projects/api/src/contracts/sync/index.ts
- https://github.com/trakt/trakt-api/blob/master/projects/api/src/contracts/users/subroutes/hidden.ts

## Live validation (2026-09-07)

Authenticated API checks and replay through the production merge confirmed:

- A first paused episode is returned by playback but absent from Up Next and
  watched history; the merged feed includes it with the correct progress.
- Two paused episodes of the same new show produce one card for the newer one.
- Hidden-season responses contain both `season` and parent `show`; the merge
  suppresses checkpoints for that season.
- A real dropped-show response suppresses a matching synthetic checkpoint.
- Watched history with `extended=noseasons` returns pagination headers and no
  season breakdown. Up Next's advertised counts can exceed returned rows.

One provider inconsistency remains: dropping the new, unwatched test show
reported an added show, but subsequent dropped-list reads omitted it, using
either IMDb or Trakt IDs for the write. This does not establish the cause of the
provider behavior; the app cannot infer a dropped state absent from its reads.

Temporary checkpoint/visibility changes were removed. Original checkpoint
positions and timestamps, watched counts and timestamps, and hidden/dropped
records were compared against the baseline. No watched history was added.
Account payloads and credential-access scripts were not committed. These checks
exercise the API and merge, not the complete player-to-Home UI flow.
