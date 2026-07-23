/// Simkl API constants.
///
/// Unlike Trakt, the PIN flow needs no client secret — Simkl's public flows
/// (PIN/PKCE) are secret-free by design, so there's nothing sensitive to hide
/// here either.
library;

const String kSimklClientId =
    '0631fe322a3107170567c72013708af7df580174efced0ed1ba96fbd71e94e93';

const String kSimklApiBaseUrl = 'https://api.simkl.com';

const String kSimklPinUrl = '$kSimklApiBaseUrl/oauth/pin';
String simklPinPollUrl(String userCode) => '$kSimklPinUrl/$userCode';
