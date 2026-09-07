# Collections (Nuvio / Xperience-style folder imports)

Debrify imports **collections JSON** files — the format Nuvio and Xperience
use to describe named groups of "folders", where each folder bundles one or
more Stremio addon catalogs, native TMDB sources or public Trakt lists. Every imported collection becomes a row of folder
tiles on the Home screen; opening a folder browses its catalogs.

## Importing

Settings → **Home Screen** → **Collections**:

| Action | Behaviour |
|---|---|
| Import from file | Pick a `.json` on the device |
| Import from link | Download the JSON from an http(s) URL |
| Paste JSON | Paste the file contents into a text box |

Imports **merge**: a collection whose `id` already exists is replaced in place
(keeping its show/hide state); new ids are appended. Tapping a collection
offers editing, JSON export, hide-from-Home and delete; "Remove all" is under Danger Zone. Documents
over 8 MiB are refused. Persisted collection definitions have an 8 MiB
aggregate limit per profile and a maximum of 1,024 live collections. Pending
deletion records do not consume these definition limits, and changing visibility
does not grow the measured definition size. An import that would grow beyond
either limit fails before saving. Large inventories are compressed before saving; the device preference budget still applies.
Profile changes during a picker or download cancel the import; failed storage
writes are reported as failures.

Collections are per profile and are included in **Backup & Restore**
(`homeCollections` in the backup payload).

## File format

The parser accepts:

- a bare list of collections (the Nuvio / Xperience export — see below),
- `{ "collections": [ … ] }`,
- a single collection object,
- a bare list of folders (imported as one collection named "Imported").

```json
[
  {
    "id": "ee8e31f3-…",
    "title": "Streaming",
    "pinToTop": false,
    "showAllTab": true,
    "backdropImageUrl": null,
    "folders": [
      {
        "id": "dd534772-…",
        "title": "Netflix",
        "hideTitle": true,
        "coverImageUrl": "https://…/netflix.webp",
        "heroBackdropUrl": "https://…/netflix.backdrop.webp",
        "titleLogoUrl": "https://…/netflix.logo.webp",
        "tileShape": "LANDSCAPE",
        "catalogSources": [
          { "addonId": "app.xperience.…", "type": "movie",  "catalogId": "streaming_netflix_movies", "genre": null },
          { "addonId": "app.xperience.…", "type": "series", "catalogId": "streaming_netflix_series", "genre": null }
        ],
        "sources": [
          { "provider": "addon", "addonId": "app.xperience.…", "type": "movie", "catalogId": "streaming_netflix_movies", "genre": null }
        ]
      }
    ]
  }
]
```

Field notes:

- `sources` is read first, preserving mixed-provider order; legacy `catalogSources`
  are also read and de-duplicated. Providers `addon`, `tmdb` and `trakt` load
  directly. Unknown providers are retained and reported as unsupported.
- `tileShape`: `LANDSCAPE` (16:9, default), `PORTRAIT` (2:3) or `SQUARE`,
  respected per folder even when one row mixes shapes.
- `coverEmoji`: cover fallback when image artwork is absent or fails.
- `hideTitle`: draw no text over the cover (the art carries the brand).
- `focusGifUrl`: animated art played over the tile while it is focused or
  hovered. `focusGifEnabled` defaults to true when omitted; explicit false
  disables the GIF.
- `heroBackdropUrl`, `titleLogoUrl`: the backdrop and logo shown above the
  folder's lists when it is opened. A missing folder backdrop falls back to
  collection `backdropImageUrl`, then the cover; a missing logo falls back to text.
- `focusGlowEnabled` (on the collection, default `true`): adds a halo tinted
  from the folder's cover when its tile is focused or hovered. `false` removes
  this extra halo while retaining the theme's normal focus indicator. Supported
  across Classic, Spotlight and the stage Home layouts.
- `focusVideoUrl` (on the folder): an HTTP(S) video played muted and looping
  from the beginning after a 350 ms focus/hover dwell. `focusVideoEnabled`
  defaults to `true`; an explicit `false` disables it. Video takes precedence
  over focus GIFs. The cover stays visible while loading; failed videos fall
  back to the GIF when present, otherwise the cover. An eight-second
  first-frame timeout prevents a stalled preview from owning playback forever.
  Focus loss, route changes, app backgrounding, and content playback stop the
  preview. Reduced-motion mode disables both animated focus media types.
  The active preview temporarily suspends other ambient trailers, and native
  disposal finishes before the next ambient decoder is created. Android TV
  tiles use a 480px-high texture to support clipping and focus transforms.
- `pinToTop`: a newly imported row leads the Home board, including when a
  saved Home Rows order already exists; otherwise collection rows sit
  after the tracker list rows and before addon catalog rows. Rows can be
  re-arranged or hidden under **Home Screen → Home Rows** like any other row
  (row id `collection:<id>`).
- `showAllTab`: the folder browser offers an "All" view merging every list.
- Records without an `id` get a stable one derived from their title, so
  re-importing the same file updates rather than duplicates.
- `viewMode`: `TABBED_GRID` selects tabs; `FOLLOW_LAYOUT` selects rows. If
  omitted, the profile setting applies.
- `heroVideoUrl`: muted looping video in the opened folder’s hero background,
  with still-art fallback and the same playback lifecycle/reduced-motion rules
  as focus previews.

The glow flag follows [Nuvio’s collection model](https://github.com/NuvioMedia/NuvioTV/blob/dev/app/src/main/java/com/nuvio/tv/domain/model/Collection.kt).
Its artwork-derived appearance follows the same intent as
[Nuvio’s glow component](https://github.com/NuvioMedia/NuvioTV/blob/dev/app/src/main/java/com/nuvio/tv/ui/components/CollectionCardGlow.kt), using Debrify’s existing
small-image color extractor and focus styling. `focusVideoUrl` is accepted from
community exports; it is distinct from Nuvio’s `heroVideoUrl`.

Existing imported records cannot recover fields that an older build discarded.
Re-import the original collection JSON to restore its video URLs and any
explicit visual preferences and native source definitions. The new fields persist through
profile storage, sync, re-import, visibility changes and Backup & Restore.

## Addon resolution

Each source names an addon by its Stremio manifest id (`addonId`) plus a
catalog `type` and `catalogId`. On the device the source is resolved against
the installed catalog addons:

An enabled addon must match the manifest id or installed local id and serve the
requested browsable catalog. Catalog type aliases (`tv`/`show`/`series` and
`movie`/`movies`) are normalized. An `all` type resolves only when the catalog id
has one unambiguous type. Catalog ids are provider-local: another addon's `top`
or `popular` is not a compatible substitute.

Settings and the folder browser distinguish an absent addon, a disabled addon,
and an installed addon without the requested catalog. Partial failures remain
visible alongside working lists. Installing/enabling the matching addon or
correcting its catalog configuration takes effect without re-importing.

## Native sources

TMDB supports `LIST`, `COLLECTION` (franchise), `COMPANY`, `NETWORK`, `DISCOVER`,
`PERSON` (cast), and `DIRECTOR` (directing credits). Sources preserve media type,
filters, sort order, artwork, and pagination. Whole lists, franchises and credits
are split into 20-title local pages; only the requested page is enriched with
IMDb identities. Non-original LIST sorting collects all remote catalog pages
and sorts the complete snapshot before exposing local pages. Original order
continues loading remote pages on demand. Raw snapshots are reused for subsequent
pages, and paginated list responses retain their remote cursor across retries. TMDB results resolve to IMDb IDs
for normal metadata, watched filtering and stream addon lookup; titles without
an IMDb mapping retain their TMDB IDs. Failed lookups retry when opening a title.

Public Trakt lists use a numeric `traktListId`, movie/TV media type, ascending or
descending order, and rank, added, title, released, runtime, popularity,
percentage or votes sorting. Private, deleted or empty remote lists cannot
supply titles; the browser reports request failures and allows retry.

TMDB builds use `TMDB_READ_ACCESS_TOKEN` from Dart defines. Local configuration
is in the ignored `.env.local.json`; release workflows inject the GitHub secret.
TMDB attribution appears in Settings → About. These sources provide metadata;
playback still uses the app's configured stream providers.

## Creating, editing and exporting

Choose **Create collection**, or open an existing collection's **Edit** action.
The editor supports collection appearance and layout, folders, artwork, source
configuration and ordering. Folder and source arrows reorder entries. Save
persists the draft; cancelling leaves the existing collection unchanged.

**Export JSON** offers clipboard copy or a file saved to a chosen location.
The export retains addon/native sources and visual settings in the import format.

## Browsing a folder

Each catalog in a folder is its own **list**. The folder browser has two
layouts. Imported `viewMode` takes precedence; otherwise the per-profile
"Tabbed folders" switch under Settings → Home Screen → Collections applies:

- **Rows** (default): one horizontal rail per list, each with a See All into
  the regular catalog browser (opened on the source's `genre`). Collections
  with `showAllTab` also offer an "All" view.
- **Tabs**: one list at a time as a full poster grid, chosen from a List chip,
  with the same "All" entry when the collection enables it.

The "All" view pages every list together into one merged, de-duplicated grid
(round-robin interleaved, bounded fan-out). Items open through the normal
detail page and Quick Play.

## Lists, Home rows and the Home Rows manager

- Every folder appears in **Home Screen → Home Rows** as a group
  ("Streaming › Netflix") with one switch per list. Switched-off lists are
  left out of every folder view. These switches only hide or show; lists are
  arranged through the collection editor.
- The collection's own Home row (its folder tiles) is a normal row in the
  Collections group there: it can be hidden or dragged anywhere.
- A catalog claimed by a visible, enabled collection folder is **folder-only**: it no
  longer appears as a plain Home row, and it is listed under its folder rather
  than under its addon in Home Rows. Hiding the collection (Settings → Home
  Screen → Collections), or hiding its row in Home Rows, returns those catalogs
  to the board unless they were independently hidden. Search and Discover keep
  their normal catalog access because those modes do not show collection rows.

## Persistence and WebDAV sync

Local inventories use `remote_home_collections_v2`; the original
`home_collections_v1` remains a readable fallback and older-build snapshot.
Small values contain a version-2 inventory:
`{ "version": 2, "records": { "collection-id": { … } }, "order": [ … ] }`.
Values larger than 64 KiB use a version-3 gzip/base64 envelope. Merged
inventories exceeding one 32 MiB envelope use version-4 independently bounded
chunks, so the union of valid imports remains editable. Local import growth
still stops at 8 MiB. Decompression is bounded per chunk and across the complete
inventory (520 MiB); encoded chunk containers are capped at 256 MiB. Device
preference budgets continue to apply, particularly on tvOS.

Collection JSON exports remain Nuvio-compatible arrays. Full profile backups
put plain version-2 inventories of at most 128 KiB under the legacy key.
Larger inventories are stored as bounded string chunks in a `collectionInventory`
extension of the preference section, covered by the package integrity digest.
Older readers ignore that extension and show a compatibility omission notice;
they do not restore an oversized legacy value. New readers restore the complete
inventory from the extension into compact storage. Sanitized shareable settings
exclude collections through their existing allowlist. Downgrading preserves the new
store, but an older build only displays its legacy snapshot and cannot use
native sources or newer visual fields.

Mutations prepare outside the profile preference write barrier and compare the
captured value again at commit, retrying if a concurrent sync changed it. WebDAV
sync stores one stamped record per collection ID, with a separate order record.
Independent imports on different devices merge; simultaneous edits to the same
collection use the existing sync stamp ordering. Deleting a collection retains
a local null marker until sync moves the deletion into its normal tombstone
tier. The engine journals that tombstone before clearing the marker, including
across an interrupted apply or publication. Published deletions follow the
shared 90-day retention policy and dormant-device protection. A deliberate later
reimport may restore a collection; a newer edit on another device, including a
visibility change, may also win over an older deletion under the stamp rules.

Reads salvage valid collection records if another record is damaged. Settings
shows a recovery notice with **Reset damaged collections**; explicit backup
restore can also repair the inventory. Ordinary imports refuse to overwrite
damaged local data until it is reset or restored. Backup exports include the
valid records. Malformed collection entries are skipped during sync, and a wholly
undecodable local inventory is treated as empty for that sync build, so it cannot
stop unrelated profiles from syncing.

Incoming sync changes refresh Home, an open folder, and collection settings.
Unrelated settings notifications preserve loaded folder pages and TV focus;
actual folder configuration changes restore focus to the folder control.
The limit on local growth also allows a merged oversized inventory to be
reduced. Ordinary WebDAV hot sections keep their original 1 MiB cap.
Collection definitions and ordering travel in separate `collections-v2` chunks
(up to 32 MiB each), published through the same atomic manifest. Obsolete chunk
references are removed when the inventory shrinks. Older builds continue to
sync ordinary state but do not receive new collection changes. Collection
records use normal last-writer-wins ordering regardless of serialization version;
no released build previously synced collections. Unchanged collection chunks
reuse their existing manifest references, even when resume state changes.

Native source IDs are persisted independently of titles and unknown imported
fields. Stored and freshly imported sources without an explicit ID share the
same functional identity calculation; explicit saved IDs are retained. Duplicate
entries pointing to the same remote list retain
separate IDs. Previously stored focus GIFs retain the old renderer's animation
behavior; fresh imports still honor an explicit `focusGifEnabled: false`.

IMDb enrichment uses two workers and a three-second page budget, with its own
request gate so catalog fetching remains available during an identity outage.
The cache still coalesces repeated external-ID lookups. Unresolved titles remain
browsable. Opening one shows progress and Cancel, accepts a replacement
selection, and falls back after four seconds; obsolete results cannot navigate.

Catalog paging advances by the raw response count, including filtered-out or
overlapping results. An empty raw catalog response means the end, including
`{}` and `{"metas": null}`, consistent with Home and See All. Failed requests
and wrongly typed `metas` values show a retryable state. In All, one source's
filtered or overlapping window does not interrupt another source's progress;
no-progress becomes retryable only when the shared attempt budget is exhausted. All shares an eight-request-per-source budget for each
page attempt, including filtered and duplicate-only windows. Retry bypasses the
cache for the retried rail request, then normal cache use resumes. Initial rail
loads and the merged view use bounded concurrency; retries retain the selected
list and TV focus returns to content when it becomes available.

## Code map

| Piece | File |
|---|---|
| Schema, parser, row-id grammar | `lib/models/home_collection.dart` |
| Store (`remote_home_collections_v2`), import (file/URL/paste), addon resolution | `lib/services/home_collections_store.dart` |
| Atomic inventory and durable deletions | `lib/models/home_collection_inventory.dart` |
| Per-catalog raw cursor and retry state | `lib/services/collection_catalog_pager.dart` |
| Native TMDB/Trakt requests and identity resolution | `lib/services/collection_native_source_service.dart` |
| Collection/folder/source editor | `lib/screens/collections/collection_editor_screen.dart` |
| Merged multi-catalog paging | `lib/services/collection_folder_loader.dart` |
| Home row section (`HomeCollectionSection`) | `lib/services/home_collection_rows.dart` |
| Folder browser screen | `lib/screens/collections/collection_folder_screen.dart` |
| Rail "See all" pill (TV focus rung) | `lib/widgets/collections/rail_see_all_pill.dart` |
| Settings page | `lib/screens/settings/collections_settings_page.dart` |
| Single-field prompt dialog (link / paste import) | `lib/widgets/text_prompt_dialog.dart` |
| Board wiring | `lib/screens/search_screen.dart` — `_buildCollectionSections`, `_openCollectionFolder`, `_openCollectionScreen` |
| Home Rows manager group | `lib/screens/settings/home_sections_filter_page.dart` |
| Backup / restore | `lib/services/backup_restore_service.dart` (`homeCollections`) |
| Tests | `test/home_collections*_test.dart`, `test/collection_catalog_pager_test.dart`, WebDAV engine tests |

On tvOS, incoming collections that exceed the preference storage budget are
deferred without blocking resume or watched updates. Collection settings shows
a capacity notice; the existing local collections remain available. The engine
retains the remote target and a local snapshot across restarts, so unchanged
local data cannot overwrite pending remote changes. Reducing the shared inventory
on another device lets collection application resume automatically.

A TMDB list with no sort selected preserves author order and fetches only the
requested remote page. Explicit sorting gathers the complete list before local
paging, with a 50-remote-page limit and an instruction to use Original order
for larger lists. Large inventory encoding, decoding and shard preparation run
in background isolates. Local edits prepare outside the preference write barrier
and retry against a fresh value if a concurrent sync changes the inventory.

Upgrade migrations compare normalized collection records on both sides of the
sync baseline. Storage version markers do not count as edits; unchanged records
retain both their original wire value and timestamp. An interrupted first apply
without a baseline or local inventory cannot invent an empty collection order.

Raw TMDB list snapshots are shared by rails and All-view readers. A repeated
first-page read reuses the snapshot; idle snapshots expire after five minutes.
Unrelated Home settings refreshes do not cancel an active title selection.
Collection section caching has a separate 64 MiB budget, so shards larger than
the ordinary 4 MiB cache can be reused without evicting ordinary hot state.

Recovered backup records retain a corruption marker for the settings notice.
Restore staging honors the tvOS preference budget and aborts without publishing
a new generation if the restored data cannot fit.
