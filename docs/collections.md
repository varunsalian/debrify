# Collections (Nuvio / Xperience-style folder imports)

Debrify imports **collections JSON** files — the format Nuvio and Xperience
use to describe named groups of "folders", where each folder bundles one or
more Stremio addon catalogs. Every imported collection becomes a row of folder
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
offers hide-from-Home and delete; "Remove all" is under Danger Zone. Documents
over 8 MiB are refused. Persisted collection definitions have a 128 KiB
aggregate limit per profile and a maximum of 1,024 live collections. Pending
deletion records do not consume these definition limits, and changing visibility
does not grow the measured definition size. An import that would grow beyond
either limit fails before saving. This leaves space for the profile's other sync data.
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

- `catalogSources` and `sources` describe the same catalogs; both are read and
  de-duplicated. Only `provider: "addon"` sources are used.
- `tileShape`: `LANDSCAPE` (16:9, default), `PORTRAIT` (2:3) or `SQUARE`.
- `hideTitle`: draw no text over the cover (the art carries the brand).
- `focusGifUrl`: animated art played over the tile while it is focused or
  hovered (`focusGifEnabled` is ignored; community files set the URL without
  the flag).
- `heroBackdropUrl`, `titleLogoUrl`: the backdrop and logo shown above the
  folder's lists when it is opened; the cover stands in for a missing
  backdrop, the title for a missing logo.
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
- Unknown fields (`viewMode`, `heroVideoUrl`, …) are ignored. `heroVideoUrl`
  describes the opened folder’s hero background, not a tile focus preview.

The glow flag follows [Nuvio’s collection model](https://github.com/NuvioMedia/NuvioTV/blob/dev/app/src/main/java/com/nuvio/tv/domain/model/Collection.kt).
Its artwork-derived appearance follows the same intent as
[Nuvio’s glow component](https://github.com/NuvioMedia/NuvioTV/blob/dev/app/src/main/java/com/nuvio/tv/ui/components/CollectionCardGlow.kt), using Debrify’s existing
small-image color extractor and focus styling. `focusVideoUrl` is accepted from
community exports; it is distinct from Nuvio’s `heroVideoUrl`.

Existing imported records cannot recover fields that an older build discarded.
Re-import the original collection JSON to restore its video URLs and any
explicit `focusGlowEnabled: false` setting. The new fields persist through
profile storage, sync, re-import, visibility changes and Backup & Restore.

## Addon resolution

Each source names an addon by its Stremio manifest id (`addonId`) plus a
catalog `type` and `catalogId`. On the device the source is resolved against
the installed catalog addons:

Only an addon whose manifest id equals `addonId` and serves the requested
browsable catalog is used. Catalog ids are provider-local: another addon's
`top` or `popular` is not a compatible substitute. A file from a deployment
with a different manifest id needs its source ids updated to the installed
provider before those sources can resolve.

Sources that resolve to nothing are skipped. The settings page and the import
result dialog list the missing addon ids, and a folder whose sources all fail
shows an explanatory empty state. Installing the addon is enough; no re-import
is needed.

## Browsing a folder

Each catalog in a folder is its own **list**. The folder browser has two
layouts, chosen by the per-profile "Tabbed folders" switch under Settings →
Home Screen → Collections:

- **Rows** (default): one horizontal rail per list, each with a See All into
  the regular catalog browser (opened on the source's `genre`). Collections
  with `showAllTab` also offer an "All" view.
- **Tabs**: one list at a time as a full poster grid, chosen from a List chip,
  with the same "All" entry when the collection enables it.

The "All" view pages every list together into one merged, de-duplicated grid
(round-robin interleaved, bounded fan-out). Items open through the normal
detail page and Quick Play of the addon that served them.

## Lists, Home rows and the Home Rows manager

- Every folder appears in **Home Screen → Home Rows** as a group
  ("Streaming › Netflix") with one switch per list. Switched-off lists are
  left out of every folder view. These switches only hide or show; lists are
  never arranged, since they live inside the folder.
- The collection's own Home row (its folder tiles) is a normal row in the
  Collections group there: it can be hidden or dragged anywhere.
- A catalog claimed by a visible, enabled collection folder is **folder-only**: it no
  longer appears as a plain Home row, and it is listed under its folder rather
  than under its addon in Home Rows. Hiding the collection (Settings → Home
  Screen → Collections), or hiding its row in Home Rows, returns those catalogs
  to the board unless they were independently hidden. Search and Discover keep
  their normal catalog access because those modes do not show collection rows.

## Persistence and WebDAV sync

The local `home_collections_v1` preference now contains a version-2 inventory:
`{ "version": 2, "records": { "collection-id": { … } }, "order": [ … ] }`.
Existing array preferences are read and upgraded on the next mutation. Legacy
backup exports remain Nuvio-compatible arrays of present collections.

Mutations read and write within the profile preference mutation barrier. WebDAV
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
The limit on local growth also allows an older or merged oversized inventory
to be reduced. The shared WebDAV hot-document limit still applies to the whole
profile; this feature does not remove that existing aggregate limit. Use the
updated implementation on each device that edits collections; the original PR's
array-only store cannot read the upgraded inventory.

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
| Store (`home_collections_v1`), import (file/URL/paste), addon resolution | `lib/services/home_collections_store.dart` |
| Atomic inventory and durable deletions | `lib/models/home_collection_inventory.dart` |
| Per-catalog raw cursor and retry state | `lib/services/collection_catalog_pager.dart` |
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
