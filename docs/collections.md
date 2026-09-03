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
over 8 MB are refused.

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
- `pinToTop`: the row leads the Home board; otherwise collection rows sit
  after the tracker list rows and before addon catalog rows. Rows can be
  re-arranged or hidden under **Home Screen → Home Rows** like any other row
  (row id `collection:<id>`).
- `showAllTab`: the folder browser offers an "All" view merging every list.
- Records without an `id` get a stable one derived from their title, so
  re-importing the same file updates rather than duplicates.
- Unknown fields (`viewMode`, `focusGlowEnabled`, focus video URLs, …) are
  ignored.

## Addon resolution

Each source names an addon by its Stremio manifest id (`addonId`) plus a
catalog `type` and `catalogId`. On the device the source is resolved against
the installed catalog addons:

1. an addon whose manifest id equals `addonId`, else
2. any installed addon that serves a catalog with the same `type` and
   `catalogId` (a file made against a different deployment of the same addon
   still works).

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
- A catalog claimed by an enabled collection folder is **folder-only**: it no
  longer appears as a plain Home row, and it is listed under its folder rather
  than under its addon in Home Rows. Hiding the collection (Settings → Home
  Screen → Collections) returns those catalogs to the board.

## Code map

| Piece | File |
|---|---|
| Schema, parser, row-id grammar | `lib/models/home_collection.dart` |
| Store (`home_collections_v1`), import (file/URL/paste), addon resolution | `lib/services/home_collections_store.dart` |
| Merged multi-catalog paging | `lib/services/collection_folder_loader.dart` |
| Home row section (`HomeCollectionSection`) | `lib/services/home_collection_rows.dart` |
| Folder browser screen | `lib/screens/collections/collection_folder_screen.dart` |
| Rail "See all" pill (TV focus rung) | `lib/widgets/collections/rail_see_all_pill.dart` |
| Settings page | `lib/screens/settings/collections_settings_page.dart` |
| Single-field prompt dialog (link / paste import) | `lib/widgets/text_prompt_dialog.dart` |
| Board wiring | `lib/screens/search_screen.dart` — `_buildCollectionSections`, `_openCollectionFolder`, `_openCollectionScreen` |
| Home Rows manager group | `lib/screens/settings/home_sections_filter_page.dart` |
| Backup / restore | `lib/services/backup_restore_service.dart` (`homeCollections`) |
| Tests | `test/home_collections_test.dart` |
