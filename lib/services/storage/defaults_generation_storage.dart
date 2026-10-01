import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/sidebar_storage.dart';
import 'package:debrify/services/storage/theme_storage.dart';

final class DefaultsGenerationStorage {
  const DefaultsGenerationStorage._();

  // ── Update-aware defaults ─────────────────────────────────────────────
  //
  // "Default" in this app has always meant "what an unset pref falls back
  // to" — which never reaches users who installed before a redesign. The
  // defaults GENERATION makes a flagship-look change reach them once:
  // on the first launch at a new generation, every look pref the user
  // NEVER wrote adopts the current bundle; every stored key — an explicit
  // choice, since all these setters write unconditionally — is untouched.
  // After migration the adopted values are stored too, so switching away
  // later sticks forever.
  //
  // Generation 1 (2026-08): the Spotlight era — Spotlight theme, Showcase
  // details, Spotlight TV home, pill rails on TV and desktop/tablet.
  // (text_brightness is deliberately absent: its unset default is already
  // the Look's value.)
  //
  // Generation 2 (2026-08): ambient trailers on, everywhere. Both surfaces
  // used to default by form factor — the hero off on phones and tablets,
  // the detail backdrop off on televisions — so most installs only ever saw
  // one of them. Both now default on for every device, and this generation
  // carries that to installs already in the field.
  //
  // Generation 3 (2026-08): Debrify TV joins the flagship bundle. Installs
  // wearing the Spotlight THEME (via the Look or a custom mix) adopt the
  // rail+stage layout; every other install keeps the grid it has always had.
  //
  // To roll out a future flagship look: bump the generation, append its
  // bundle under a `gen < N` block below.
  // Generation 4 repairs profiles imported with a remote defaults checkpoint
  // but without its device-local appearance values. Fill only absent keys;
  // explicit Looks and custom settings remain unchanged.
  // Generation 5 enables source logos and original add-on formatting once.
  static const int _currentDefaultsGeneration = 5;
  static const String _defaultsGenerationKey = 'defaults_generation';

  /// MUST run before [TextBrightnessController.warm] / theme warms in
  /// `main()`: the first frame has to already be the migrated look.
  static Future<void> migrateDefaultsGeneration() async {
    final prefs = await ProfilePreferences.instance();
    final gen = prefs.getInt(_defaultsGenerationKey) ?? 0;
    if (gen >= _currentDefaultsGeneration) return;
    if (gen < 4) {
      // Dormant prefs are written too (desktop pill on a phone, TV home
      // style off-TV): harmless where they don't apply, correct if the
      // device class — or a window size — ever changes.
      //
      // The theme and its `detail_theme` mirror move as a PAIR, in the
      // controller's write-through order (mirror first — old builds read
      // only the mirror, and Showcase resolves its palette from it). The
      // pairing also means an explicit legacy pick (app_theme stored, no
      // mirror by design) keeps its details page untouched.
      if (!prefs.containsKey(ThemeStorage.appThemeKey)) {
        if (!prefs.containsKey(DetailPageStorage.detailThemeKey)) {
          await prefs.setString(DetailPageStorage.detailThemeKey, 'spotlight');
        }
        await prefs.setString(ThemeStorage.appThemeKey, 'spotlight');
      }
      const bundle = <String, String>{
        DetailPageStorage.detailPageStyleKey: 'showcase',
        HomeAppearanceStorage.tvHomeStyleKey: 'spotlight',
        SidebarStorage.tvSidebarStyleKey: 'pill',
        SidebarStorage.desktopSidebarStyleKey: 'pill',
      };
      for (final entry in bundle.entries) {
        if (!prefs.containsKey(entry.key)) {
          await prefs.setString(entry.key, entry.value);
        }
      }
    }
    if (gen < 2) {
      // Both ambient trailer surfaces, for installs whose form factor used to
      // default one of them off. An explicit off — the toggles write
      // unconditionally, so a stored `false` is always a real choice — is left
      // alone: this turns trailers on for people who never had an opinion, not
      // for people who said no.
      const trailers = <String, bool>{
        'home_hero_trailer_enabled': true,
        'detail_trailer_autoplay_enabled': true,
      };
      for (final entry in trailers.entries) {
        if (!prefs.containsKey(entry.key)) {
          await prefs.setBool(entry.key, entry.value);
        }
      }
    }
    if (gen < 4) {
      // Debrify TV joins the flagship bundle. Raw prefs only — this runs
      // before any mirror is warmed, so `app_theme` is read directly rather
      // than through `appThemeCached`. The appearance block above has already
      // written `app_theme` for anyone who never chose, including a fresh
      // install, so this read is never against an absent key on a migrated
      // install.
      //
      // NOT unconditional the way generation 1 was: this key has never
      // existed, so `!containsKey` is true for every install on earth, and a
      // blanket 'spotlight' would restyle every Classic user AND flip their
      // Presets picker to Custom (Classic pins this key). The proxy is the
      // THEME, not Look activity — a Custom mix that kept the Spotlight
      // theme adopts the layout the theme implies; everyone else keeps grid.
      if (!prefs.containsKey(DebrifyTvStorage.debrifyTvStyleKey)) {
        final theme = prefs.getString(ThemeStorage.appThemeKey);
        await prefs.setString(
          DebrifyTvStorage.debrifyTvStyleKey,
          theme == 'spotlight' ? 'spotlight' : 'grid',
        );
      }
    }
    if (gen < 5 && prefs.getBool('sources_presentation_defaults_copied_v1') != true) {
      await prefs.setBool('sources_show_addon_logos', true);
      await prefs.setBool('sources_use_addon_text', true);
    }
    await prefs.setInt(_defaultsGenerationKey, _currentDefaultsGeneration);
  }
}
