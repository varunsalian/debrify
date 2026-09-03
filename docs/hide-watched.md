# Hide watched titles

Settings → **Tracking** → **Hide watched** → "Hide watched titles". Off by
default, saved per profile, and included in Backup & Restore as `hide_watched`
inside the tracking-preferences payload.

When ON, movies you have finished and shows you have completed disappear from
the catalog surfaces:

- Home board rows (addon catalogs) and their horizontal paging
- the Spotlight hero reel
- catalog search results
- See All grids and Discover's catalog source
- Trakt's discovery lists (Trending, Popular, Anticipated, Recommendations) on
  Home and in Discover / See All
- MDBList public "top" lists on Home and the MDBList catalog browse

Never hidden, because they are your own lists rather than catalogs:

- Continue Watching (every provider)
- My Watchlist and the Favorites rows
- Trakt History, Watchlist, Collection, Ratings, your custom and liked lists
- every Simkl list (Plan to Watch, Watching, Completed, …)
- your own and liked MDBList lists
- IPTV

## What "watched" means

The same answer that draws the ✓ on posters (`WatchedStatusService`): a union
of what you finished in Debrify, your Trakt watched history, and Simkl and
MDBList "completed", **masked by the Watched-ticks selection** on the same
settings page. So the ✓ and the hiding always agree. For shows it means the
whole show is finished (every aired episode locally, or fully watched on the
tracker), never "saw one episode". Only movies and series with an IMDb id can
be matched; anything else passes through.

## Paging

Filtering a page can leave it short or empty, so paged surfaces fetch through
`fetchFilteredPage`, which keeps pulling windows until enough titles survive
(default 12, at most 4 windows) and treats only a raw-empty window from the
addon as the end of the catalog. Skip offsets advance by the addon's raw counts
so paging stays aligned. With the switch off it is exactly one fetch, so
nothing changes for anyone who leaves it off.

## Timing

Decisions are pinned at fetch time. Finishing a movie does not rip it out of a
row you are looking at; it is gone on the next board load. On a cold start the
board waits (at most 1.5 s) for the local watched snapshot before fetching, so
the first paint is already filtered; tracker histories arrive asynchronously
and apply from the next load.

## Code

| Piece | Where |
|---|---|
| Switch (sync cache, warmed in `main()` and on profile switch) | `lib/services/hide_watched_prefs.dart` |
| Predicate over `WatchedStatusService` (`hides`, `apply`, `predicate`) | `lib/services/watched_filter.dart` |
| Top-up pager (`fetchFilteredPage`) | `lib/services/filtered_catalog_pager.dart` |
| Snapshot readiness (`hasSnapshot`, `firstSnapshot`) | `lib/services/watched_status_service.dart` |
| Which Trakt lists filter (`TraktSeeAllList.hidesWatched`) | `lib/services/trakt/trakt_list_source.dart` |
| Home board, row paging, hero reel, catalog search | `lib/screens/search_screen.dart` |
| See All / Discover grids | `lib/screens/see_all/catalog_see_all_screen.dart` |
| Trakt / MDBList rows and See All | `lib/services/home_list_rows.dart`, `lib/screens/see_all/{trakt,mdblist}_see_all_screen.dart` |
| Settings toggle, search leaf, backup payload | `lib/screens/settings/tracking_settings_page.dart`, `lib/screens/settings_screen.dart`, `lib/services/storage_service.dart` |
| Tests | `test/hide_watched_test.dart` |

## Design decisions

- **Watchlist rows are exempt.** Hiding titles from "my list" would make the
  list lie about its contents; the switch is about catalogs the user browses.
- **The Watched-ticks mask is reused** rather than a separate source
  selection, so there is one mental model: the ✓ and the hiding use the same
  histories. Swapping `isWatchedForTicks` for `isWatched` in `WatchedFilter`
  would make the switch independent of ticks.
- **Series threshold is "fully watched"**, inherited from the tick logic. A
  "hide once started" variant would be a progress-based feature like the
  Trakt See All watched/unwatched chip, not this switch.
- **No live removal.** `WatchedStatusService` is a `ChangeNotifier`, so
  re-running `WatchedFilter.apply` over the loaded sections on change would be
  a small follow-up if immediacy is ever wanted.

## Not yet covered

Collection folders (the collections feature on its own branch) are not wired
yet; the intended change is to run the folder loader through
`fetchFilteredPage` in the same way.
