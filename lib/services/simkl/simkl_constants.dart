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

const String kSimklPinUrl = '$kSimklApiBaseUrl/oauth/pin';
String simklPinPollUrl(String userCode) => '$kSimklPinUrl/$userCode';
