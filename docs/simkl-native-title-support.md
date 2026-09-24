# Simkl titles without IMDb IDs

Implemented 2026-09-24.

## Confirmed report

The public Simkl response for Big Brother (2023), `/tv/2274121?extended=full`, contains Simkl ID `2274121`, TMDB ID `237243`, and TVDB ID `440642`, but no IMDb ID. The old transformer and Continue Watching parser dropped it.

## Behavior

- Preserve validated IMDb, TMDB, or Simkl IDs, in that order. Native IDs remain namespaced and never populate the IMDb metadata field.
- Continue Watching joins sparse playback IDs against explicit library aliases, preserves paused/up-next coordinates, and distinguishes movie/show TMDB namespaces.
- Simkl reads, writes, and scrobbles send the actual provider ID. `/sync/watched` uses the documented flat identifier object with `type: show`; other sync endpoints retain nested `ids`.
- Native TV guides use TMDB's exact title/season endpoints, or Simkl's TV episodes endpoint for Simkl-only IDs. No title-based original/revival remapping is performed.
- Search can open a TMDB title even when IMDb enrichment returns no match. Sources and next-episode navigation retain its native ID.
- Native episode selections are not treated as custom addon videos, so existing IPTV matching remains available.
- IPTV quick-play accepts validated TMDB/Simkl identities while retaining direct-link and source-mode restrictions, deferred episode resolution, and movie-year matching.
- Simkl removal clears paused sessions before removing the library entry, retaining aliases for sparse playback IDs. A failed lookup or cleanup retains the library entry for retry. Movie resets use the same sequence.
- TMDB movie progress keys use `tmdb:movie:<id>`; TV keeps `tmdb:<id>`. Local Continue Watching, completion, and reset operations keep these identities separate. Simkl and addon boundaries convert movie progress keys back to provider IDs.
- IMDb-only tracker destinations are excluded for native identities. Local progress is isolated by native identity rather than shared display title.

API contract reference: https://raw.githubusercontent.com/SIMKL/API/master/apiary.apib

## Verification

188 regression tests pass across Simkl, metadata navigation, native guides, local-history isolation, watched actions, existing custom catalogs, and TMDB browsing. Phone/TV widget tests assert actual Simkl watched progress and the ID/coordinates passed to Sources. Static analysis of changed code has no errors or warnings; existing informational lint findings remain.

Two unrelated `collection_native_browser_test.dart` cases fail on unchanged HEAD as well: `Spotlight Home folder opens all rows directly` for iOS and Android with `TV false`. They expect Recent/Popular shelves but receive All titles. The final regression command excludes exactly those two cases.

After the IPTV quick-play review fix, all 100 focused IPTV, quick-play rules, and native Simkl regression tests pass. These include TMDB/Simkl episode discovery and resolution, malformed-ID rejection, source-mode restrictions, and native movie-year matching. Focused analysis reports only existing informational lints.

No authenticated production watch history was modified. No release or installation was performed.

## Live acceptance remaining

Using the affected account and a build with its existing TMDB configuration:

1. Refresh Simkl and confirm Big Brother (2023) appears in Continue Watching.
2. Open it and compare Season 4 watched ticks and next episode with Simkl.
3. Open Sources and verify the user's IPTV provider supplies the expected episode; provider catalog coverage and title naming are separate from ID handling.
4. Play/pause an episode and verify Simkl progress resumes after reopening the app.
5. Confirm any older Big Brother entry retains its own local history.

These account/provider checks and physical-device playback have not been performed in this change.
