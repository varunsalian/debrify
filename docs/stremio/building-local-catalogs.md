# Build Your Own Stremio TV Catalogs

Stremio TV lets you create your own channel lineups by importing JSON catalogs. You can build a catalog by hand, host it somewhere and import it by URL, keep it in a repo, or generate one from Trakt.

This guide is for advanced users who want to create the catalog JSON itself. If you just want to use Stremio TV inside the app, start with the main Stremio TV guide first.

> All examples here match the logic in `LocalCatalogImporter` inside `lib/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart`.

## 1. Quick start

If you want the shortest path:

1. Create a `.json` file with:
   - a catalog `name`
   - a catalog `type`
   - an `items` array
2. Make sure every item has:
   - `id`
   - `name`
3. Import it in Debrify from:
   - `Stremio TV -> Import -> From File`

A minimal catalog looks like this:

```json
{
  "name": "My Movie Channel",
  "type": "movie",
  "items": [
    {
      "id": "tt0111161",
      "name": "The Shawshank Redemption"
    }
  ]
}
```

## 2. Catalog schema

Each catalog is a JSON object with three core fields:

```json
{
  "name": "My Sci-Fi Movies",
  "type": "movie",
  "items": [
    { /* entries */ }
  ]
}
```

| Field | Required? | Description |
| --- | --- | --- |
| `name` | ✅ | Display name shown in the Stremio TV catalog chooser. Must be unique locally. |
| `type` | Optional (defaults to `movie`) | Either `movie` or `series`. Helps Debrify pick the right layout and filter Trakt refreshes. |
| `items` | ✅ | Array of catalog entries (see next section). Must contain at least one entry. |

Catalog IDs are auto-generated, so you never include `id` at the top level.

## 3. Item schema

Every entry inside `items` must be a JSON object with an `id` and `name`. Everything else is optional but strongly recommended for a richer UI.

```json
{
  "id": "tt4154796",
  "name": "Avengers: Endgame",
  "type": "movie",
  "year": 2019,
  "overview": "After the devastating events of Infinity War...",
  "rating": 8.4,
  "poster": "https://image.tmdb.org/t/p/w500/or06FN3Dka5tukK1e9sl16pB3iy.jpg",
  "fanart": "https://image.tmdb.org/t/p/w1280/ulzhLuWrPK07P1YkdWQLZnQh1JL.jpg",
  "genres": ["Action", "Adventure", "Sci-Fi"]
}
```

| Field | Required? | Notes |
| --- | --- | --- |
| `id` | ✅ | Unique identifier. IMDB IDs work great, but any stable string is fine. |
| `name` | ✅ | Title shown in the channel list. |
| `type` | Optional | `movie` or `series`. Only needed if your catalog mixes formats. |
| `year` | Optional | Number or string. Debrify will try to parse it into an integer. |
| `overview` | Optional | Short blurb shown in detail view. |
| `rating` | Optional | Numeric rating (IMDB, Trakt, personal score, etc.). |
| `poster` | Optional | URL to poster artwork. |
| `fanart` | Optional | URL to a wide background image. |
| `genres` | Optional | Array of strings. |

> Validation rules: the importer rejects any catalog where `name` is empty, `items` is missing, or an item lacks `id` or `name` (see `LocalCatalogImporter.validate`).

## 4. Full example (movies)

```json
{
  "name": "Saturday Night Sci-Fi",
  "type": "movie",
  "items": [
    {
      "id": "tt0083658",
      "name": "Blade Runner",
      "type": "movie",
      "year": 1982,
      "overview": "Deckard hunts down rogue replicants in a neon-soaked LA.",
      "poster": "https://image.tmdb.org/t/p/w500/qAhedRxRYWZAgZ8O8pHIl6QHdD7.jpg",
      "fanart": "https://image.tmdb.org/t/p/w1280/zRiF4oYBArW2dVnmlwZ9bkJ4J41.jpg",
      "genres": ["Sci-Fi", "Thriller"]
    },
    {
      "id": "tt0119116",
      "name": "The Fifth Element",
      "type": "movie",
      "year": 1997,
      "overview": "A cab driver becomes central to saving the world.",
      "poster": "https://image.tmdb.org/t/p/w500/fPtlCO1yQtnoLHOwKtWz7db6RGU.jpg",
      "genres": ["Action", "Sci-Fi"]
    }
  ]
}
```

Save this as `saturday-sci-fi.json` then open the **Stremio TV** tab in Debrify and use the `Import` menu → `From File`.

## 5. Import options

On the Stremio TV tab, tap the **Import** button (gear icon in the action row) and choose from five sources:

1. **From file** – Choose a `.json` file via the system picker (`FilePicker`). The filename (without `.json`) becomes the catalog name if you’re importing a Trakt list.
2. **From URL** – Paste a direct link to raw JSON. Debrify downloads the content (HTTP GET) and runs the same validation.
3. **Paste JSON** – Paste the object directly into the dialog (handy for quick experiments).
4. **Browse repo** – Opens the built-in Stremio TV repo browser. Pick a catalog hosted on GitHub/community repos.
5. **From Trakt** – Sign in with Trakt, then select watchlist/history/trending/custom/liked lists. Debrify fetches the items via `TraktService`, converts them to the catalog schema, and remembers the source so you can refresh later.

> All import paths end in the same local catalog format, so once your JSON is valid you can import it in whichever way is most convenient.

## 6. Trakt-specific behavior

When the importer detects a raw Trakt list (JSON array where entries contain `movie`/`show` objects):

- **Name required** – Because Trakt exports lack a root `name`, you must supply one (dialog input or filename).
- **Auto-transform** – Debrify runs `TraktItemTransformer.transformList` to map Trakt metadata into the catalog schema (IDs, posters, fanart, etc.).
- **Split mixed lists** – If the list contains both movies and shows, Debrify creates two catalogs (e.g., `My List — Movies` and `My List — Series`).
- **Refresh metadata** – Trakt imports store `traktSource`, `traktSlug`, and `traktOwner` so the "Refresh from Trakt" button knows how to fetch fresh items.

## 7. Tips & gotchas

- **Unique names** – The importer rejects catalogs if another local catalog already uses the same `name`.
- **IMDB IDs recommended** – Not required, but using IMDB IDs makes Trakt/metadata lookups more reliable.
- **Storage location** – Catalogs live in Debrify’s local storage (via `StorageService.addStremioTvLocalCatalog`). Clearing app data or reinstalling removes them.
- **Type consistency** – If you set `type: "movie"` but include shows, the UI still displays them, but Trakt refresh filters by type and may drop mismatching entries.

## 8. Quick checklist

- [ ] JSON object with `name`, optional `type`, and `items` array
- [ ] Every item has `id` + `name`
- [ ] Optional metadata (poster, fanart, overview) to make the UI look great
- [ ] File saved as `.json`
- [ ] Import via file/URL/paste/repo, or convert a Trakt list through the "From Trakt" dialog

Design your own themed channels, share catalog files with friends, or host them in a repo and load them via URL—the importer treats them all the same. Happy curating!
