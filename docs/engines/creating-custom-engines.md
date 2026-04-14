# Build a Torrent Engine (No Dart Required)

Want Debrify to speak to your favorite torrent indexer? All you need is a single YAML file. This guide keeps the moving parts simple, shows how the pieces fit, and gives you a verified template you can copy immediately.

## Fast track

1. **Duplicate an engine** from the GitLab catalog ([`mediacontent/search-engines/torrents`](https://gitlab.com/mediacontent/search-engines/-/tree/main/torrents)), rename the file, and update the fields you need.
2. **Edit with the cheat sheet below.** Debrify uses a flat YAML schema (no nested JSON objects to fight).
3. **Test your API call** in Postman/Insomnia until you know the JSON paths you'll map.
4. **Import the YAML** through *Addons → Import Engine*. The UI copies the file into local storage, clears caches, and reloads running engines.
5. **Search in Debrify** (keyword). Watch the console output from `EngineExecutor` for URLs, pagination steps, and field-mapping errors.
6. **Iterate**: tweak the YAML, re-import (same filename), repeat.

## Engine anatomy cheat sheet

| Section | Why it exists | Must-haves |
| --- | --- | --- |
| `id`, `display_name`, `icon`, `categories`, `capabilities` | Tell Debrify how to present your engine. | Unique `id`, at least one capability toggled on. |
| `api`, `query_params`, `path_params`, `request` | Describe the HTTP request(s). | `api.urls` with placeholders like `{imdb_id}` when needed. |
| `series_config` | Optional helpers for IMDB/series search. | Only when `series_support: true`. |
| `pagination` | How to fetch multiple pages (page/cursor/offset/none). | `type` plus the knobs for that type. |
| `response_format`, `field_mappings`, `special_parsers`, `transforms`, `empty_check` | Turn raw JSON into `Torrent` objects. | `field_mappings` for at least `infohash` and `name`. |
| `settings` | User-facing toggles/dropdowns/sliders. | At least the `enabled` toggle. |
| `tv_mode` | Android TV channel limits. | Skip if your engine isn't TV-friendly. |

## Section-by-section

### 1. Metadata & capabilities

```yaml
id: pirate_bay
display_name: "The Pirate Bay"
icon: sailing
categories: [general, movies]
capabilities:
  keyword_search: true
  imdb_search: true
  series_support: false
```

Tips:
- `id` must be unique and usually matches the filename (`pirate_bay.yaml`).
- Toggle capabilities to control when the UI sends traffic to you. If you only support IMDB IDs, set `keyword_search: false`.

### 2. Requests & URL builders

```yaml
api:
  urls:
    keyword: "https://apibay.org/q.php"
    imdb: "https://apibay.org/q.php"
  base_url: "https://apibay.org"
  method: GET
  timeout_seconds: 10
  params:
    - name: limit
      value: "100"
      location: query

query_params:
  type: query_params
  param_name:
    keyword: q
    imdb: q
  encode: true

# Use path_params when URLs contain placeholders
path_params:
  type: path_params

series_config:
  max_season_probes: 5
  default_episode: 1
```

What to remember:
- `api.urls` can include placeholders `{imdb_id}`, `{season}`, `{episode}`. Debrify swaps them automatically.
- Use `api.params` for constants (limit, sort, auth headers). Set `location: query`, `body`, or `header`.
- `query_params.param_name` accepts a single string (`q`) or a map keyed by search type.
- `path_params` switches the URL builder into template mode—needed for engines like Torrentio.
- Add a top-level `request` block only when you need to override generic settings (e.g., a longer timeout).

### 3. Pagination

```yaml
pagination:
  type: page           # none | page | cursor | offset
  page_size: 100       # alias for results_per_page
  max_pages: 5
  start_page: 1
  page_param: "page"
  has_more_field: "pagination.hasNext"
```

Other options:
- **Cursor**
  ```yaml
  pagination:
    type: cursor
    cursor_field: "meta.next"
    cursor_param: "cursor"
  ```
- **Offset**
  ```yaml
  pagination:
    type: offset
    offset_param: "offset"
    start_offset: 0
  ```

Set only the knobs your API understands. `EngineExecutor` stops automatically once it hits `max_pages`, `fixed_results`, or an empty batch.

### 4. Response parsing & field mapping

```yaml
response_format:
  type: jina_wrapped        # direct_json | jina_wrapped | custom proxy
  extract_json: true        # unwraps https://r.jina.ai/ responses
  results_path: "results"   # string or per-search-type map
  pre_checks:
    - field: "success"
      equals: true

empty_check:
  type: field_value
  field: "[0].name"
  equals: "No results returned"

field_mappings:
  infohash:
    source: "info_hash"
  name:
    source: "title"
    conversion:
      type: replace
      find: "\\n"
      replace: " "
  size_bytes:
    source: "size"
    conversion: string_to_int
  seeders:
    source: "seeders"
    conversion: string_to_int
  leechers:
    source: "leechers"
    conversion: string_to_int

special_parsers:
  seeders:
    source: "title"
    type: regex
    pattern: "seeders:\s*(\d+)"
    capture_group: 1
    conversion: string_to_int
```

Helpful reminders:
- `response_format.type` is `direct_json` for normal APIs, `jina_wrapped` when you tunnel through `https://r.jina.ai/...`.
- `results_path` accepts dot notation (`data.items`) or a map: `{ keyword: 'search.results', imdb: 'data' }`.
- `field_mappings` must produce at least `infohash` and `name`; everything else improves sorting/filtering.
- Inline `conversion` values cover simple cases (`string_to_int`, `unix`, `lowercase`). Complex jobs can use a map describing the transform, or a separate `special_parsers` entry (regex, size-with-unit, etc.).
- `FieldMapper` discards torrents if `infohash` is empty or all zeros—double-check that mapping first.

### 5. Settings

`settings` is a list. Each entry becomes a UI control under the engine configuration card.

```yaml
settings:
  - id: enabled
    type: toggle
    label: "Enable SolidTorrents"
    default: true
  - id: max_results
    type: dropdown
    label: "Maximum Results"
    default: 100
    options: [100, 200, 300]
```

Supported controls:
- `toggle` → boolean on/off
- `dropdown` → pick from `options`
- `slider` → requires `min`, `max`, `default`

### 6. TV Mode (optional)

```yaml
tv_mode:
  enabled_default: false
  limits:
    small: 10
    large: 25
    quick_play: 15
```

Leave this block out if the engine doesn't make sense for Android TV channels.

## Copy & paste starter

```yaml
# Minimal keyword-only engine
id: example_indexer
display_name: "Example Indexer"
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false

api:
  urls:
    keyword: "https://example.com/api/search"
  method: GET

query_params:
  type: query_params
  param_name: q

pagination:
  type: none

response_format:
  type: direct_json
  results_path: results

field_mappings:
  infohash:
    source: hash
  name:
    source: title
  size_bytes:
    source: size
    conversion: string_to_int
  seeders:
    source: seeders
    conversion: string_to_int
  leechers:
    source: leechers
    conversion: string_to_int

settings:
  - id: enabled
    type: toggle
    label: "Use Example Indexer"
    default: true
```

Import this file, search for anything, and confirm it shows up in the engine picker. Then expand it with pagination, IMDB support, and TV-mode settings as needed.

## Testing & debugging checklist

- **Mirror the request manually.** Copy the URL/body from the console (logged by `EngineExecutor`) into Postman to confirm the remote API behaves.
- **Validate paths early.** Before you edit YAML, write down the JSON path to `infohash`, `name`, `seeders`, etc.
- **Watch pagination logs.** Each request prints "Fetching page X from ...". If it never goes past page 1, check `has_more_field`, cursor extraction, or `results_per_page`.
- **Debug field mapping.** Temporarily add `debugPrint(rawResult)` inside `lib/services/engine/field_mapper.dart` or set a breakpoint in `FieldMapper.mapToTorrent`.
- **Reset when stuck.** `LocalEngineStorage.clearAll()` wipes every imported engine, handy if you corrupted a file.
- **Honor defaults.** Anything you omit inherits values from `assets/config/engines/_defaults.yaml`.

## Importing engines

Whether you built the engine for yourself or plan to share it, the delivery path is the same: bundle the YAML and import it through the in-app **Addons → Import Engine** flow (or the matching web uploader). The GitLab catalog is curated, so nobody outside the core team pushes directly to `torrents/` or `metadata.yaml`. Distribute the YAML manually and remember the importer consumes it verbatim—never embed API keys or secrets.

## How the pipeline works (if you're curious)

| Stage | What happens | Source file(s) |
| --- | --- | --- |
| 1. Remote catalog | `RemoteEngineManager` lists/downloads YAML files from GitLab. | `lib/services/engine/remote_engine_manager.dart` |
| 2. Local vault | `LocalEngineStorage` saves the YAML + metadata under the app's documents directory. | `lib/services/engine/local_engine_storage.dart` |
| 3. Config loader | `ConfigLoader` merges `_defaults.yaml`, reshapes the flat YAML into `EngineConfig`. | `lib/services/engine/config_loader.dart` |
| 4. Registry | `EngineRegistry` keeps live `DynamicEngine` instances and exposes capability filters. | `lib/services/engine/engine_registry.dart` |
| 5. Execution | `DynamicEngine` + `EngineExecutor` run HTTP requests, pagination, and response parsing. | `lib/services/engine/dynamic_engine.dart`, `lib/services/engine/engine_executor.dart` |
| 6. UI | The Engine Import page lets you import/delete/reload engines. | `lib/screens/settings/engine_import_page.dart` |

Keep this table handy when debugging—logs from any layer immediately tell you which box misbehaved.

You now have everything needed to teach Debrify how to talk to almost any torrent indexer. Happy hacking!
