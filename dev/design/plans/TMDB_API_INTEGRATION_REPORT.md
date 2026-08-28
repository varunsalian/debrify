# TMDB API Integration Report for Debrify

Reviewed against Debrify's current worktree and the official TMDB v3/v4 documentation on August 24, 2026.

No implementation work was performed as part of this report.

## Executive conclusion

TMDB would fit Debrify very well as its primary:

- Metadata and ID-resolution layer
- Artwork and title-logo provider
- Movie, series, season, and episode discovery source
- Cast, crew, people, and filmography source
- Franchise and collection browser
- Region-aware streaming-availability source
- Localized title, description, date, and certification source

It should not replace:

- Trakt, Simkl, and MDBList scrobbling, history, progress, calendars, or personalized tracking
- Debrify's local continue-watching and local watchlist behavior
- Stremio addons as stream and catalog providers
- IMDb Parents Guide, trivia, quotes, goofs, Top 250, Metacritic, or awards data
- TVMaze as an immediate fallback until TMDB episode coverage has been proven in practice

The strongest strategy is a hybrid:

> TMDB becomes the canonical metadata backbone; IMDb IDs remain the playback and search interoperability key; trackers remain user-state authorities; Stremio and TVMaze become fallbacks or specialized sources.

## 1. Current Debrify state

Debrify has no first-class TMDB client today. Its central content model already acknowledges `tmdb:` IDs but primarily stores an IMDb ID and a small metadata subset: title, poster, backdrop, overview, year, IMDb rating, genres, runtime, trailer, and logo (`lib/models/stremio_addon.dart`).

Metadata currently comes from several independent paths:

- Cinemeta performs movie title/year-to-IMDb resolution and supplies catalog metadata (`lib/services/movie_metadata_service.dart`).
- Stremio addons provide catalogs, detailed metadata, episode lists, logos, trailers, and recommendation links.
- Undocumented IMDb GraphQL supplies cast, runtime, certificates, ratings, awards, trivia, quotes, goofs, connections, companies, box office, and Metacritic (`lib/services/imdb_enrichment_service.dart`).
- TVMaze fills episode metadata and artwork gaps after Stremio (`lib/services/episode_artwork_service.dart`).
- Trakt, Simkl, and MDBList provide discovery and user state. Trakt alone currently exposes continue watching, watchlist, history, collection, ratings, recommendations, trending, popular, and anticipated surfaces (`lib/services/trakt/trakt_list_source.dart`).
- Debrify also has its own tracker-independent local movie/series watchlist (`lib/screens/search_screen.dart`).

This works, but it means metadata quality and availability depend on multiple third-party or undocumented interfaces. TMDB can consolidate much of that read-only metadata surface.

## 2. Best integration opportunities

| Priority | Debrify surface | TMDB APIs | Recommended use |
| --- | --- | --- | --- |
| P0 | Universal ID resolution | `/find/{external_id}`, external IDs | Resolve IMDb IDs into stable TMDB movie/TV IDs and preserve both. This is the foundation for everything else. |
| P0 | Detail screens | Movie/TV details plus appended responses | Hydrate sparse Stremio, Trakt, Simkl, MDBList, local-watchlist, and catalog items consistently. |
| P0 | Episode browser | TV, season, and episode details/images | Supply season structure, episode names, overviews, air dates, runtime, stills, guest cast, and crew. |
| P0 | Artwork | Configuration plus movie/TV/season/episode/person images | Posters, backdrops, title logos, episode stills, cast portraits, and localized artwork. |
| P1 | Discover | Discover Movie/TV, genre, certification, provider configuration | Add a powerful account-free TMDB Discover source. |
| P1 | Home rows | Trending and standard movie/TV lists | Trending, Now Playing, Upcoming, Airing Today, On the Air, Popular, and Top Rated. |
| P1 | Watch Next | Recommendations, similar titles, collections | Stable fallback when a Stremio addon does not provide recommendation links. |
| P1 | Where to watch | Movie/TV/season watch providers | Show legal streaming, rental, and purchase availability by region. |
| P1 | Cast navigation | People details and combined credits | Make cast cards navigable and introduce filmography pages. |
| P1 | Franchise navigation | Collections and TV episode groups | Replace part of the fragile IMDb Universe dependency with structured franchise browsing. |
| P1 | Search | Movie, TV, multi, person, collection, company, keyword search | Improve title matching and introduce people and collection discovery. |
| P2 | Localization | Translations and configuration languages/countries | Localized titles, overviews, certifications, artwork, and dates. |
| P2 | TMDB account | Favorites, watchlist, ratings, custom lists | Optional fourth tracker/library integration, not required for metadata. |
| P3 | Cache invalidation | Change lists and per-item changes | Useful only for a persistent metadata database or server-side cache. |

### P0: Canonical ID resolution

Debrify's playback flows depend heavily on IMDb IDs. That should continue because torrent searches, Stremio IDs, Trakt, Simkl, and other integrations often interoperate through IMDb.

TMDB's `/find/{external_id}?external_source=imdb_id` can resolve an IMDb ID into movies, TV shows, people, and episodes. It also supports TVDB, Wikidata, and several social identifiers. This is materially better than fuzzy title/year matching when an external ID already exists.

Official documentation: <https://developer.themoviedb.org/reference/find-by-id>

Recommended identity record:

- `tmdbId`
- `imdbId`
- Media type
- Optional TVDB/Wikidata identifiers
- Original source/content ID
- Resolution confidence or exactness

Do not replace IMDb IDs with TMDB IDs. Store both and convert at integration boundaries.

### P0: Detail-screen metadata hydration

For movie and TV details, TMDB can provide:

- Localized and original title
- Overview and tagline
- Runtime or episode runtime
- Release and air dates and status
- Genres
- Production companies, networks, and countries
- Spoken languages
- Budgets and revenue for movies
- Vote average and count
- Poster and backdrop paths
- Collection membership
- Season summary and next/last episode information

Detail calls support `append_to_response` with up to 20 child requests, allowing one response to include credits, images, external IDs, videos, recommendations, keywords, certifications, and more.

Official documentation:

- <https://developer.themoviedb.org/reference/movie-details>
- <https://developer.themoviedb.org/docs/append-to-response>

This would reduce the current dependence on:

- Cinemeta for routine metadata
- Undocumented IMDb GraphQL for basic plot, runtime, cast, and genres
- A recommendation-capable Stremio addon merely to make the detail page complete

Important presentation rule: label TMDB votes as `TMDB`, not `IMDb`. They are different rating populations.

### P0: Episodes and seasons

TMDB has structured endpoints for:

- Series details and season inventory
- Season details, aggregate credits, images, videos, translations, and providers
- Episode details, credits, guest stars, still images, videos, translations, and external IDs
- Alternate episode groups: original air order, absolute, DVD, digital, story arc, production, and TV order

Season and episode details also support appended responses.

Official documentation:

- <https://developer.themoviedb.org/reference/tv-season-details>
- <https://developer.themoviedb.org/reference/tv-episode-details>
- <https://developer.themoviedb.org/reference/tv-episode-group-details>

This integrates directly into:

- Episode panels and grids
- Tracker calendar cards
- Continue-watching episode thumbnails
- Season source selection
- Next-episode presentation
- Anime absolute-order or DVD-order handling

TMDB should initially precede TVMaze in the fallback chain, not immediately remove TVMaze:

1. Stremio episode metadata when already fetched for playback
2. TMDB structured season/episode metadata
3. TVMaze fallback
4. Series artwork fallback

### P0: Artwork

TMDB exposes posters, backdrops, logos, profile images, and episode stills. Image URLs must be constructed using values from `/configuration`, rather than assuming a permanent base URL or size set.

Official documentation: <https://developer.themoviedb.org/docs/image-basics>

Recommended Debrify mappings:

- Poster grids: appropriately sized poster rendition
- TV hero: backdrop rendition sized for the display class
- Detail identity: localized TMDB logo, then existing title-text fallback
- Episode cells: still image
- Cast rail: profile image
- Franchise page: collection backdrop/poster
- Provider badges: provider logo
- Studio/network UI: company/network logos

For localized images, query the user's language plus `null` as fallback. TMDB explicitly recommends `include_image_language`, because ordinary language filtering can otherwise hide suitable language-neutral artwork.

Official documentation: <https://developer.themoviedb.org/docs/image-languages>

### P1: TMDB Discover

TMDB Discover is one of the strongest product additions. Movie discovery supports more than 30 filter and sort options, including:

- Release-date and year ranges
- Certification ranges and country
- Genres and excluded genres
- Keywords and excluded keywords
- Cast, crew, and people
- Production companies
- Country and original language
- Runtime range
- Vote average and vote-count thresholds
- Watch provider, region, and monetization type
- Popularity, revenue, release date, title, and rating sorts

Comma-separated filter values generally mean AND; pipe-separated values mean OR.

Official documentation: <https://developer.themoviedb.org/reference/discover-movie>

This overlaps well with MDBList's existing catalog filters for media type, genre, country, language, score, year, date, runtime, and sorting (`lib/services/mdblist/mdblist_discover_models.dart`).

Recommended UI integration:

- Add `TMDB` as a Discover source, not a torrent search engine.
- Reuse the MDBList filter interaction model where possible.
- Add provider and monetization filters that MDBList currently lacks.
- Preserve TMDB result order until the user explicitly changes sorting.
- Require a sensible vote-count floor for Top Rated; otherwise obscure titles with very few votes dominate.

TMDB can also power Debrify TV recipes based on genre, keywords, actors, studios, language, decade, or runtime. It should supply the title lineup; existing engines and debrid services should continue resolving playable sources.

### P1: Home and discovery rails

Useful account-free rows include:

- Trending movies, TV, people, or mixed; daily or weekly
- Movies: Now Playing, Popular, Top Rated, Upcoming
- TV: Airing Today, On the Air, Popular, Top Rated

Trending is short-window daily/weekly interest, whereas popularity is a longer-term score. They should be separate row concepts.

Official documentation: <https://developer.themoviedb.org/docs/popularity-and-trending>

TMDB's On the Air covers shows airing during the next seven days and is essentially a predefined Discover query. It is not a personalized calendar.

Official documentation: <https://developer.themoviedb.org/reference/tv-series-on-the-air-list>

Therefore:

- Keep Trakt, Simkl, and MDBList calendar rows for `my upcoming episodes`.
- Use TMDB for editorial rows such as `Airing This Week`.
- Allow Home-row opt-in so TMDB does not overwhelm tracker and addon rows.

### P1: Recommendations, similar titles, and franchises

Use distinct labels:

- **Recommendations:** TMDB's recommendation relationship
- **Similar:** Primarily based on genre and plot keywords; TMDB warns that results may not always be strong
- **Collection:** Explicit movie franchise membership

Official documentation:

- <https://developer.themoviedb.org/reference/movie-recommendations>
- <https://developer.themoviedb.org/reference/movie-similar>
- <https://developer.themoviedb.org/reference/collection-details>

Suggested detail hierarchy:

1. Existing Stremio Watch Next, when available, because an addon may have domain-specific recommendations
2. TMDB Recommendations
3. More Like This from TMDB Similar
4. Collection/franchise rail when applicable

TMDB collections are excellent for film franchises but do not reproduce every IMDb relationship such as `remade as`, `spin-off from`, or `follows`. Keep IMDb Universe data as optional enrichment if it remains reliable.

### P1: Watch-provider availability

TMDB provides region-specific flatrate, free, ad-supported, rental, and purchase availability for movies, TV series, and TV seasons. Data is supplied through JustWatch. It does not provide service-specific deep links; it provides a TMDB link and enough data to display availability. JustWatch attribution is mandatory.

Official documentation:

- <https://developer.themoviedb.org/reference/movie-watch-providers>
- <https://developer.themoviedb.org/reference/tv-series-watch-providers>
- <https://developer.themoviedb.org/reference/tv-season-watch-providers>

Good placements:

- Detail page `Available on` strip
- Discover filters
- Search-result badges
- A region-aware `Streaming now` Home row

This must remain visually and semantically separate from Debrify's debrid/source picker. Provider availability describes licensed availability; it is not a playable source returned to Debrify.

### P1: People, cast, and crew

Person APIs cover:

- Person details
- Movie, TV, and combined credits
- Images
- Tagged images
- External IDs
- Translations
- Popular people
- Change history

Official documentation: <https://developer.themoviedb.org/reference/person-combined-credits>

This enables:

- Tappable cast cards
- Actor/director pages
- Known-for rails
- More from this director
- Discover by cast or crew
- Better person-image fallback

It is a meaningful new feature, not just metadata replacement.

### P2: TMDB user accounts

TMDB user authentication can support:

- Favorites
- Movie and TV watchlists
- Movie, TV, and episode ratings
- Custom lists
- Account-state checks on detail screens

The v4 authorization flow supports a mobile callback: create a temporary request token, open TMDB approval, then exchange the approved request token for a user access token.

Official documentation: <https://developer.themoviedb.org/v4/docs/authentication-user>

V4 is preferable for new authentication and mixed-media custom lists; v3 sessions remain useful for established account endpoints.

However, TMDB does not replace Trakt, Simkl, or MDBList because it does not offer Debrify's required:

- Playback heartbeats and scrobbling
- Watched-history semantics
- Resume positions
- Next-to-watch progress
- Personalized episode calendar
- Collection tracking equivalent to Trakt
- Now-playing state

Recommendation: defer TMDB account support until the metadata/discovery integration is mature. If added, expose it as an optional library integration, not as `the new tracker`.

Guest sessions are only suitable for rating movies, TV shows, and episodes and must still be treated as private tokens.

Official documentation: <https://developer.themoviedb.org/docs/authentication-guest-sessions>

## 3. Complete relevant API-family inventory

| TMDB family | Available operations | Debrify decision |
| --- | --- | --- |
| Authentication | Validate key; guest session; v3 request token/session; v4 request/access tokens; logout; v4-to-v3 conversion | Application auth required; user auth optional later |
| Account | Details, favorites, watchlists, rated movies/TV/episodes, custom lists, account states, mutations | Optional tracker/library integration |
| Certifications | Movie and TV certification configuration | Use for filters, badges, and profile restrictions |
| Changes | Changed movie/TV/person IDs and field-level movie/TV/person/season/episode changes | Use only with persistent long-lived caches |
| Collections | Details, images, translations | Use for franchise rails and pages |
| Companies | Details, alternative names, images | Use for studio pages and filters |
| Configuration | Image config, countries, jobs, languages, translations, timezones | Required foundation and cacheable static data |
| Credits | Credit-record lookup | Low-frequency support for detailed cast/crew navigation |
| Discover | Movie and TV advanced filtering | High-value Discover source and channel-recipe input |
| Find | Resolve external identifiers | Essential identity bridge |
| Genres | Movie and TV genre lists | Required for filters and genre-ID mapping |
| Guest sessions | Retrieve a guest's rated movie/TV/episode lists | Only if guest rating is exposed |
| Keywords | Keyword details and associated movies | Use for thematic discovery and Debrify TV |
| Lists v3 | Legacy list details/create/add/remove/check/clear/delete | Avoid for new mixed-media list work |
| Lists v4 | Create, read, update, add/remove, clear, delete, item status | Preferred if TMDB custom lists are added |
| Movies | Details, credits, images, videos, external IDs, keywords, releases, reviews, recommendations, similar, providers, translations, account state/rating | Core metadata |
| Movie lists | Now Playing, Popular, Top Rated, Upcoming | Home and Discover rows |
| Networks | Details, images, alternative names | Useful TV metadata and filter navigation |
| People | Details, images, credits, external IDs, translations, popular, changes | Cast/person experience |
| Reviews | Review details and title-review lists | Optional; lower product value than existing detail features |
| Search | Collection, company, keyword, movie, multi, person, TV | Core search and navigation |
| Trending | All/movie/TV/person, day/week | Home and Discover rows |
| TV series | Details, aggregate/regular credits, content ratings, episode groups, images, keywords, recommendations, similar, videos, providers, translations, account rating | Core series metadata |
| TV lists | Airing Today, On the Air, Popular, Top Rated | Home and Discover; not a personal calendar |
| TV seasons | Details, aggregate/regular credits, images, videos, providers, translations, changes | Episode guide and season presentation |
| TV episodes | Details, credits, stills, videos, external IDs, translations, changes, account rating | Episode guide and calendar enrichment |
| TV episode groups | Alternate numbering and order definitions | Valuable for anime, DVD order, and specials |
| Watch providers | Regions, provider catalogs, movie/TV/season availability | Where to watch and Discover filters |

The official machine-readable v3 API definition is the authoritative exhaustive endpoint list:

<https://developer.themoviedb.org/openapi/tmdb-api.json>

## 4. Data TMDB cannot fully replace

Keep the current IMDb-specific path, or another licensed source, for:

- Parents Guide category severities
- Trivia, goofs, and quotes
- IMDb Top 250
- IMDb popularity meter and weekly movement
- IMDb rating and vote count
- Metacritic
- Detailed awards totals
- Some worldwide box-office presentation
- Fine-grained relationship labels such as remakes and spin-offs

TMDB can replace the basic plot, runtime, cast, genre, and company portion of the current undocumented IMDb request. The IMDb call can then become optional enrichment rather than a critical dependency.

Also retain tracker/local authority for:

- Watched and unwatched state
- Continue watching and resume percentage
- Playback scrobbling
- Personalized calendar
- Collection and history
- Next episode based on actual user history

## 5. Operational and legal requirements

### Authentication and key handling

Application-level v3 calls accept either an `api_key` parameter or a Bearer read token. The same read token works across v3 and v4.

Official documentation: <https://developer.themoviedb.org/docs/authentication-application>

A token compiled into an open-source Flutter application must be treated as public and extractable. Viable choices are:

1. **User-supplied TMDB read token/API key:** Best security and cost model for this project, but adds setup friction.
2. **Debrify-operated proxy:** Best onboarding, but introduces hosting, privacy, reliability, and abuse responsibilities.
3. **Bundled shared token:** Easiest UX but weakest control; susceptible to extraction and quota abuse.

Given Debrify already uses user-configured integrations, a user-supplied token is the most natural initial model.

User session and access tokens must be stored using the project's secret-vault/profile credential facilities, isolated by profile, excluded from backups unless explicitly protected, revoked on disconnect, and never logged.

### Limits and resilience

TMDB says the historic 40-requests-per-10-seconds limit is disabled, but approximate upper limits around 40 requests per second remain and may change. Clients must respect `429`.

Official documentation: <https://developer.themoviedb.org/docs/rate-limiting>

Recommended behavior:

- Deduplicate in-flight requests
- Cache exact IMDb-to-TMDB mappings aggressively
- Cache configuration, genres, and providers separately
- Use `append_to_response` for detail hydration
- Use exponential backoff with jitter for 429 and transient 5xx failures
- Never cache authentication failures as permanent `no metadata`
- Bound pagination; TMDB pages start at 1 and cap at 500
- Keep stale metadata available during outages
- Do not block playback on metadata failure

TMDB provides no SLA. Metadata integrations must degrade gracefully.

Official documentation: <https://developer.themoviedb.org/docs/faq>

### Attribution and licensing

Debrify is licensed under `AGPL-3.0-only`, which permits commercial use and redistribution. The project license therefore does not by itself establish noncommercial use under TMDB's developer API model. The integration must include:

- An approved TMDB logo in About/Credits
- The required notice that the product uses TMDB but is not endorsed or certified by TMDB
- JustWatch attribution anywhere watch-provider data appears
- Correct source labeling on ratings and metadata
- Cache expiration and refresh so TMDB content is not retained longer than six months
- Immediate purge capability if API authorization terminates

TMDB's terms prohibit commercial use without a written agreement and describe revenue broadly. Because Debrify displays donation links, the maintainer should obtain TMDB confirmation that the intended distribution and funding model qualifies before shipping a shared application key. This is a licensing-risk recommendation, not a legal conclusion.

Official sources:

- <https://www.themoviedb.org/api-terms-of-use?language=en-CA>
- <https://developer.themoviedb.org/docs/faq>

## 6. Recommended rollout

### Phase 1: Foundation

- Application authentication
- Configuration, countries, languages, genres, and provider regions
- Exact IMDb-to-TMDB resolution
- Persistent identity mapping
- Region and metadata-language settings
- Cache and error policy
- TMDB attribution

### Phase 2: Metadata replacement

- Movie and TV detail hydration
- Credits and person images
- Posters, backdrops, and logos
- Certifications and release dates
- Season and episode metadata
- Videos and trailers
- Preserve IMDb and TVMaze fallback paths

### Phase 3: Product features

- TMDB Discover source
- TMDB Home rows
- Recommendations, similar titles, and collections
- Cast and crew navigation
- Where-to-watch presentation
- Keyword-driven Debrify TV catalog generation

### Phase 4: Optional account integration

- V4 user authorization
- Favorites, watchlists, and ratings
- Mixed-media custom lists
- Per-profile token isolation
- Conflict rules between local, TMDB, Trakt, Simkl, and MDBList lists

### Phase 5: Advanced maintenance

- Change-driven cache refreshing
- Alternate TV episode groups
- Provider-aware discovery presets
- Certification-based profile restrictions

## Final recommendation

Proceed with TMDB, but scope the first integration as metadata infrastructure rather than another full tracker.

The highest-value initial package is:

1. IMDb-to-TMDB resolution
2. Movie, TV, season, and episode detail hydration
3. Artwork and logos
4. TMDB Discover and Home rows
5. Recommendations, people, and collections
6. Region-aware watch providers

Defer TMDB account synchronization. It duplicates existing library surfaces but cannot replace Debrify's mature tracker, scrobble, progress, calendar, or local playback behavior.
