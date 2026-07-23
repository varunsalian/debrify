/// Simkl API constants.
///
/// Unlike Trakt, the PIN flow needs no client secret — Simkl's public flows
/// (PIN/PKCE) are secret-free by design, so there's nothing sensitive to hide
/// here either.
library;

const String kSimklClientId =
    '0631fe322a3107170567c72013708af7df580174efced0ed1ba96fbd71e94e93';

const String kSimklApiBaseUrl = 'https://api.simkl.com';

// Simkl's docs list client_id/app-name/app-version as required query params
// on every request (beyond the PIN flow, which only needed client_id).
const String kSimklAppName = 'debrify';
const String kSimklAppVersion = '1.0';

/// CDN host for the pre-built trending data files (public, no auth) — a
/// different host from the main API.
const String kSimklTrendingUrl =
    'https://data.simkl.in/discover/trending/today_100.json';

/// CDN calendar file (public, no auth): upcoming episode air dates for all TV
/// shows. Simkl has no per-user calendar endpoint like Trakt's
/// `/calendars/my/shows`, so the calendar is synthesized by intersecting this
/// against the shows in the user's Simkl library (see SimklCalendarService).
/// Regenerated every ~6h and CDN-cached ~5h; query strings are ignored.
///
/// The sibling `calendar/anime.json` is deliberately NOT used: its entries
/// carry only MAL/AniDB/Simkl ids (no IMDb id) and no season number, so this
/// IMDb-keyed app can neither match them to the user's library nor open their
/// detail page — every anime entry would drop. The Simkl calendar is therefore
/// TV-shows-only, consistent with the app's existing IMDb-centric model.
const String kSimklCalendarTvUrl = 'https://data.simkl.in/calendar/tv.json';

const String kSimklPinUrl = '$kSimklApiBaseUrl/oauth/pin';
String simklPinPollUrl(String userCode) => '$kSimklPinUrl/$userCode';
