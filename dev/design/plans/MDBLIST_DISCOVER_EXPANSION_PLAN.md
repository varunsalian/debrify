# MDBList Discover Expansion Plan

**Status:** implementation in progress; all work remains uncommitted

**Validated:** 2026-08-23 against the checked-in Discover call graph, the
official OpenAPI schema, and read-only responses from the connected free-tier
account

## 1. Outcome

Replace the current MDBList list-only Discover panel with a complete, lazy,
quota-aware tracker and discovery source. The result must:

- expose MDBList Continue Watching, Watchlist, History, Collection, Ratings,
  and Dropped Shows;
- expose only recommendation sections advertised by the account, including the
  free `rising` section and supporter-only personalised sections when present;
- expose Curated, Top, Official, My, Liked, and External lists with their
  distinct response contracts;
- offer an explicit, never-prefetched MDBList Catalog browser with visible
  special-quota state and cached queries;
- preserve cursor pagination, provider-native order, partial-result honesty,
  provider progress, TV focus, and Search-to-list handoff;
- add no new coupling or behavior changes to Trakt or Simkl;
- bind every cache and in-flight publication to the current profile/account;
- make no background catalog query and never issue a catalog request merely
  because the MDBList source mounted or a filter value changed.

The following MDBList APIs are deliberately not part of this poster-grid work:
social activity, discussions, notifications, account deletion, user stats,
favorite-person feeds, and media-database update feeds.

## 2. Authoritative API mapping

| Discover surface | Endpoint(s) | Contract notes |
|---|---|---|
| Continue Watching | `/sync/playback`, `/upnext`, `/sync/watched` | Reuse the existing completion-aware CW service and progress. |
| Watchlist | `/watchlist/items` | Cursor-paged movie/show buckets. |
| History | `/sync/watched` | Show movie/show titles, not standalone episode cards. Preserve newest activity order. |
| Collection | `/sync/collection` | Movie/show view; whole-show collection semantics remain unchanged. |
| Ratings | `/sync/ratings` | Movie/show titles and user ratings. |
| Dropped Shows | `/sync/dropped` | Shows only. |
| Recommendations | `/lists/recommended`, `/lists/recommended/{section}/items` | Section discovery is authoritative. Free accounts may expose only `rising`; unavailable personalised sections must not be shown. |
| Curated Lists | `/lists/curated`, `/lists/{id}/items` | Bare list array, cursor-paged items. |
| Top Lists | `/lists/top`, `/lists/{id}/items` | Existing bare-array parser. |
| Official Lists | `/lists/official`, `/lists/official/{slug}/items` | Slug identity and a distinct item route. |
| My/Liked Lists | `/lists/user`, `/lists/liked`, `/lists/{id}/items` | Existing typed list choices and like semantics. |
| External Lists | `/external/lists/user`, `/external/lists/{id}/items` | Distinct metadata and item route. |
| Catalog | `/catalog/movie`, `/catalog/show` | Keyset pagination; response includes `quota`. Filters include genre, country, language, score, release dates/years, runtime and provider sorts. |

## 3. UX structure

Keep the existing filter-line pattern and replace the list-type `Category` with
five stable groups:

1. **Library** — Continue Watching, Watchlist, History, Collection, Ratings,
   Dropped Shows.
2. **For You** — the sections returned by `/lists/recommended`.
3. **Discover** — Official Lists, Curated Lists, and Top Lists. Selecting one
   of these directories reveals its list picker.
4. **Lists** — My Lists, Liked Lists, and External Lists. Search handoff remains
   a temporary `Search Result` entry in this group.
5. **Catalog** — explicit query builder and Apply action. No initial query.

The control sequence is:

`Source -> Category -> View -> optional List -> Show -> Sort -> actions`

Rules:

- Switching category/view clears stale items immediately and invalidates the
  old in-flight publication.
- Empty is distinct from failure, denied, partial, and quota exhausted.
- Continue Watching renders its MDBList progress bar and keeps MDBList resume
  semantics on open/quick-play.
- `Show` applies in memory except Catalog, where media type is part of the
  explicit query.
- Natural order means server order. Client A-Z/Z-A remain available for finite
  snapshots; server-paged sources use documented server sorts.
- On TV, Source remains the entry focus. DPAD-up from the grid returns to the
  nearest visible filter control and every category remains usable in the
  one-row Discover shelf.

## 4. Data architecture

Add a typed `MdblistDiscoverSource` rather than extending
`MdblistListChoice` into a union of unrelated shapes.

Required types:

- `MdblistDiscoverGroup`
- `MdblistDiscoverView`
- `MdblistDiscoverChoice` for dynamic recommendation/list choices
- `MdblistDiscoverPage` carrying items, progress, completion, next cursor,
  failure kind, and optional catalog quota
- `MdblistCatalogQuery` and `MdblistCatalogQuota`

Transport methods return `MdblistResult<T>` and parse each endpoint explicitly.
No endpoint may be treated as authoritative empty after a failure or partial
walk. Catalog cache identity includes account authority plus the normalized
query; account/profile reset invalidates both cached and in-flight publication.

## 5. Implementation phases and review gates

### Phase 1 — Library

- Add typed library view definitions and transformer coverage for direct and
  nested sync rows.
- Reuse the existing CW snapshot; add Watchlist, History, Collection, Ratings,
  and Dropped loaders.
- Wire Library into the panel with progress and meaningful empty/error states.
- Test response shapes, provider order, partial reads, stale requests, and CW
  progress.

**Gate:** no Library view can erase prior authoritative provider state or show
an episode as an independent movie/show title.

### Phase 2 — Recommendations and list discovery

- Add explicit parsers/loaders for recommendation metadata/items, curated,
  official, and external lists.
- Retain current My/Liked/Top/Search handoff and like/clone behavior.
- Add cursor-aware item loading for official/external routes.
- Show only recommendation sections returned for the current account.

**Gate:** free and supporter accounts produce valid menus without probing
forbidden sections; distinct list response shapes are never cross-cast.

### Phase 3 — Catalog

- Add normalized query and quota models.
- Add an explicit Apply flow for media type, genre, country, language, year,
  runtime, score, and sort.
- Do not query on mount, focus, dropdown selection, rebuild, or source switch.
- Cache exact queries and page cursors; surface remaining quota and expiry.
- Disable Apply when the last known special quota is exhausted unless a cached
  result exists.

**Gate:** a widget lifecycle test proves zero catalog requests before Apply and
one request per uncached Apply.

### Phase 4 — Integration hardening

- Preserve Search handoff, list like/clone actions, Random, source switching,
  Discover stage focus, and profile/account reset.
- Add focused widget/source/transport tests.
- Run formatter, analyzer on touched files, focused tests, then broader Discover
  and MDBList suites.

**Gate:** no Trakt/Simkl file needs behavioral modification; their tests remain
green and MDBList does not add eager startup requests.

## 6. Plan review iterations

### Review 1 — contract and scope

- Corrected the initial flat-list idea: endpoint response shapes and capability
  gates require typed view/choice/page models.
- Kept recommendation discovery dynamic instead of hardcoding supporter-only
  sections.
- Excluded unrelated social/account APIs and database-update feeds.

### Review 2 — correctness and lifecycle

- Added account/profile authority to cache and in-flight publication rules.
- Required last-good preservation for partial/failure refreshes.
- Separated episode history from title-grid history to prevent malformed cards.

### Review 3 — quota and performance

- Moved Catalog behind explicit Apply after the live free account reported a
  four-query special allowance.
- Prohibited mount/filter-change/background catalog requests.
- Required normalized-query caching, cursor reuse, and visible quota state.

### Review 4 — UX and regression

- Grouped the expanding menu into five categories rather than creating an
  unwieldy flat picker.
- Preserved existing Discover filter/focus conventions and Search handoff.
- Made Trakt/Simkl behavioral non-modification an explicit exit gate.

No major plan issue remains after these four passes. Implementation findings
may still revise this document before the final audit.

## 7. Implementation review iterations

### Implementation review 1 — contracts and authority

- Corrected list-directory decoding to support both bare arrays and the
  paginated `{lists, pagination}` Liked Lists envelope.
- Preserved `X-Next-Cursor`, body cursors, `X-Has-More`, and partial later-page
  failures instead of treating them as complete.
- Added an MDBList auth revision boundary so reconnect, logout, profile switch,
  and in-flight old-account responses cannot reuse or publish old Discover
  caches.

### Implementation review 2 — UI state and data honesty

- Fixed category return to Library so its loading state always settles.
- Invalidated stale item and load-more publications after category, list, media
  type, sort, filter, or account changes.
- Retained usable partial directory data and last-good pages, rejected
  standalone episode cards, and made equal-timestamp activity ordering stable.
- Kept Catalog query changes visually dirty: old results are removed and no new
  request occurs until Apply.

### Implementation review 3 — quota and performance

- Normalized and validated every query before it can spend special Catalog
  quota, including media path, score/runtime/year/date bounds, ISO country and
  language codes, all documented sorts, and sort direction.
- Disabled uncached Apply/More operations while the last known special quota is
  exhausted; cached queries remain reusable.
- Limited Catalog to explicit 100-item cursor pages, cached exact normalized
  queries, kept all other dynamic pages lazy, and used unified list responses
  so provider order is preserved without client-side reassembly.

### Implementation review 4 — regression and integration

- Formatter and diff checks pass; the analyzer reports no issue in any touched
  production or test file.
- 124 focused MDBList, Android TV progress, profile-isolation, Discover shelf,
  filter-bar, and dropdown tests pass.
- The repository-wide analyzer still reports its pre-existing patched tvOS
  package errors and legacy lint backlog; none originate in this change.
- No Trakt or Simkl implementation file changed, and Catalog lifecycle tests
  prove zero requests before Apply and no request on filter changes.

No major implementation issue remains after these four passes.
