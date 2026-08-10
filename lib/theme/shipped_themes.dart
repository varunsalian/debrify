import '../widgets/detail/theme/detail_themes.dart';

/// Which themes this build will actually draw, and how a stored value that is
/// not one of them is narrowed.
///
/// **Runtime policy, not settings UI.** This lived inside
/// `settings/detail_theme_page.dart`, which meant two production screens had to
/// import a settings PAGE to answer "what theme is this". That made the page
/// impossible to retire without breaking dispatch — so the policy moved here
/// first, and the page now re-exports it for the call sites that still name it.
///
/// Every theme this build can actually draw.
///
/// Narrower than [StorageService.kDetailThemes], which accepts all twenty so a
/// choice written by a newer build survives a downgrade. Dispatch, the Settings
/// subtitle and the picker's selected state all read [effectiveDetailTheme]
/// rather than the raw value.
///
/// ── The two light-ground themes are withheld for now ──────────────────────
///
/// `broadsheet` (#F3EFE7) and `concrete` (#C9C7C1) are the only cores whose
/// ground is light — `AppTheme.fromDetail` classifies them by
/// `ground.computeLuminance() > 0.5`, and no other core comes close.
///
/// **Bug:** text stays light-on-light and is unreadable on them. The token
/// layer flips correctly, but the screens still carrying hardcoded light text
/// literals never go through it, so they don't follow the ground when it turns
/// pale. Every dark theme hides this — a light-on-dark literal happens to be
/// right — which is why it only shows up on these two.
///
/// Withheld HERE rather than dropped from [DetailThemes.all] so the fallbacks
/// stay graceful: [effectiveDetailTheme] narrows a stored `broadsheet` to
/// `signal`, `AppThemes.byId` narrows it to legacy, and nothing is rewritten
/// on disk. Anyone already on one lands on a readable theme, and gets theirs
/// back the moment these are re-listed.
///
/// Re-enable both once the remaining literals read from the token layer.
const Set<String> kDetailThemesShipped = {
  'spotlight',
  'signal',
  'noir',
  // 'broadsheet', // light ground — unreadable text, see note above
  'phosphor',
  'aurora',
  // 'concrete',   // light ground — unreadable text, see note above
  'velvet',
  'blueprint',
  'broadcast',
  'sepia',
  'obsidian',
  'halo',
  'prestige',
  'deep_field',
  'graphite',
  'vault',
  'spectrum',
  'verdant',
  'frost',
  'cinemascope',
  // The premium set. Listed last here but shown FIRST by the pickers, which
  // read `DetailThemes.catalogue`; this set only says what may be drawn.
  'glass',
  'field',
  'hearth',
  'console',
  'reel',
};

/// The stored value narrowed to what this build can render. Never persists.
String effectiveDetailTheme(String raw) =>
    kDetailThemesShipped.contains(raw) ? raw : 'signal';

/// Row caption for the Appearance list.
String detailThemeLabel(String raw) =>
    DetailThemes.byId(effectiveDetailTheme(raw)).label;
