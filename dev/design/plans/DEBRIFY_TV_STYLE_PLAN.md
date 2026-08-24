# Debrify TV as a switchable style, defaulting to Spotlight

Ship the rail + stage from `design/mockups/debrify_tv_spotlight_mockup/` as a new
**`debrify_tv_style`** preference — the same shape as `tv_home_style`,
`detail_page_style`, `iptv_style` and `tv_sidebar_style` — and make `spotlight`
the value the Spotlight Look carries.

| What | Where | Value |
|---|---|---|
| **Grid** | today's `_buildTvGridLayout`, unchanged | `debrify_tv_style` = `grid` *(coercion target)* |
| **Spotlight** | rail + stage (TV) · list + sheet (phone) | `debrify_tv_style` = `spotlight` |
| Picker | Appearance → Debrify TV | new `DebrifyTvStylePage` |
| Bundled by | Appearance → Presets → Spotlight | `AppLooks.spotlight.values` |

The mock is the spec. It is drawn at 1920×1080; **every number is logical (÷2)**
unless stated otherwise.

---

## 1. Non-negotiables

1. **Additive.** One new pref key, two values, one new picker page. `grid` renders
   byte-identically to today on every device class.
2. **Paint only.** Every playback path — `_watch`, `_watchChannel`, the five
   provider flows, prefetch, cancel, deep-link auto-play — is shared verbatim.
   The new layout is a *view* over the existing state, never a fork of it.
3. **One press still plays.** OK on a rail row calls the same `_watchChannel`.
   RIGHT is what opens the stage's secondary actions.
4. **DPAD before paint.** Explicit node targeting, in visual order. Geometric
   traversal is forbidden. Sidebar opens only via LEFT at column 0.
5. **The stage may not promise what plays.** The mock's §3 is binding: count
   quality only, label the strip a sample, never a running order.
6. **TV cost budget.** No per-frame `Opacity`, no `BackdropFilter`, no `saveLayer`
   in a focus tick. `RepaintBoundary` around every animating card. Alpha baked
   into colours.

---

## 2. The preference

`lib/services/storage_service.dart`, modelled line-for-line on `tv_home_style`
(`:863–901`):

```dart
static const String _debrifyTvStyleKey = 'debrify_tv_style';

/// Every shipping Debrify TV layout. 'grid' is the historical default — the
/// channel wall `build()` has always drawn. Coercion is TOTAL and both ways,
/// so a value written by a newer build and read by an older one lands on
/// 'grid' rather than rendering nothing.
static const Set<String> kDebrifyTvStyles = {'grid', 'spotlight'};

static String debrifyTvStyleCached = 'grid';

static Future<String> getDebrifyTvStyle() async { … }
static Future<void> setDebrifyTvStyle(String style) async {
  final normalized = kDebrifyTvStyles.contains(style) ? style : 'grid';
  debrifyTvStyleCached = normalized;   // mirror BEFORE the await — house rule
  …
}
```

**Warm it in `main.dart` beside `getTvHomeStyle()` (`:199`)** — which is *after*
`migrateDefaultsGeneration()` (`:195`). That order is load-bearing: generation 3
writes the pref, and the warm has to read what the migration just wrote or frame
one renders the old layout.

### One key, every device class

`debrify_tv_style` is **not** TV-only. The Spotlight arm has a TV layout and a
phone layout, and the phone one is half the point — today `build()` calls
`_buildTvGridLayout` unconditionally, so a phone gets a television's grid.

This mirrors `detail_page_style`, which resolves device class *inside* the style.
**Television must be tested before any width breakpoint**, exactly as
`resolveDetailSize` does: a 1920×1080 TV is 960×540 logical, and a width-only
check sends it to the tablet arm.

---

## 3. Making Spotlight carry it — three changes, all required

This is the part with the trap in it.

### 3.1 The Spotlight bundle

```dart
// AppLooks.all → id: 'spotlight'
'debrify_tv_style': 'spotlight',
```

### 3.2 The Classic bundle must pin `grid`

```dart
// AppLooks.all → id: 'classic', beside the existing pinned layout keys
'debrify_tv_style': 'grid',
```

Not optional, and the reason is sharper than the migration one written on that
bundle today: **`isActive` only checks keys a bundle names.** A Classic that says
nothing about `debrify_tv_style` reports itself active while Debrify TV renders
the Spotlight rail — the picker and the screen contradicting each other, with
nothing to reconcile them. Pinning is about Look coherence first; the migration
consequence is §3.3's problem to solve.

### 3.3 Generation 3 — the reason this can't be skipped

`AppLook.isActive` is **detection, not storage**: it compares every key the bundle
names against what is stored right now. So the moment `debrify_tv_style` joins the
Spotlight bundle, every user *already on* the Spotlight Look has no such pref →
`read()` returns the coerced `'grid'` → `'grid' != 'spotlight'` → **the Appearance
picker silently flips them to "Custom"**, having changed nothing.

`_currentDefaultsGeneration` is at **2** today, so a new block is needed:

**It may NOT adopt unconditionally the way generation 1 did.** Generation 1 could,
because the keys it wrote already existed and a user might genuinely have chosen
one. `debrify_tv_style` has never existed, so *no* install can have written it —
`!containsKey` is true for everyone, and a blanket `spotlight` would restyle every
Classic user on earth and, because §3.2 makes Classic name the key, flip their
Presets picker to **Custom**. That is not the accepted gap from generation 1; that
gap was a minority of Classic users, this would be all of them.

So generation 3 writes the value the install's *existing* look implies:

```dart
if (gen < 3) {
  // Debrify TV joins the flagship bundle. Raw prefs only — this runs before
  // any mirror is warmed, so `app_theme` is read directly rather than through
  // `appThemeCached`. The gen<1 block above has already written `app_theme`
  // for anyone who never chose, including a fresh install, so this read is
  // never against an absent key on a migrated install.
  if (!prefs.containsKey(_debrifyTvStyleKey)) {
    final theme = prefs.getString(_appThemeKey);
    await prefs.setString(
      _debrifyTvStyleKey,
      theme == 'spotlight' ? 'spotlight' : 'grid',
    );
  }
}
```

Bump `_currentDefaultsGeneration` to 3.

| Install | `app_theme` | Gets | Why |
|---|---|---|---|
| Fresh | `spotlight` (written by gen 1 above) | `spotlight` | Flagship default |
| On the Spotlight Look | `spotlight` | `spotlight` | Stays *Spotlight*, does not flip to Custom |
| On Classic | `legacy` | `grid` | Not restyled; Classic still reports Classic |
| On Midnight / Console | other | `grid` | Their Look says nothing about this surface — don't surprise them. `isActive` is unaffected either way, since detection only compares named keys |
| Custom, theme still `spotlight` | `spotlight` | `spotlight` | **Deliberate.** The proxy is the *theme*, not Look activity: a Custom mix that kept the Spotlight theme gets the layout the theme implies. Their picker already says Custom, so nothing flips |
| Custom, other theme | other | `grid` | As Midnight / Console |

Conservative on purpose: the only installs this restyles are the ones already
wearing the Spotlight *theme* — via the Look or a custom mix — which is the
whole point of the change.

### 3.4 What NOT to build

**Do not resolve the layout from `app_theme` at read time** — "if the theme is
spotlight, render the spotlight layout." It is the obvious shortcut and it is
wrong twice over: it creates a second, competing source of truth next to the
pref, and it makes the picker lie (the page says *Grid* while the screen draws
*Spotlight*). The Look bundle plus the generation migration is how this codebase
already answers "a theme brings its layouts", and it is the answer here.

---

## 4. Every touchpoint

| File | Change |
|---|---|
| `services/storage_service.dart` | key, `kDebrifyTvStyles`, mirror, getter, setter, generation-3 block, bump the constant |
| `main.dart` | warm beside `getTvHomeStyle()` (after the migration) |
| `theme/app_looks.dart` | `LookKeys.debrifyTvStyle` — **`notify:` stays null**, see below — add to `LookKeys.all` and to both bundles |
| `screens/settings/debrify_tv_style_page.dart` | **new** — copy `iptv_style_page.dart`: choices list, `debrifyTvStyleLabel()`, `_firstCardMarker` TV focus seeding, and `LookApplier.noteExternalWrite('debrify_tv_style')` before the set |
| `screens/settings/widgets/settings_widgets.dart` | `SettingsRows.debrifyTvAppearance` |
| `screens/settings_screen.dart` | state field, load in the batch at `:284` — **append at the END of the `Future.wait` list**: the results are consumed positionally (`results[23]`-style), so inserting mid-list shifts every index after it — `_openDebrifyTvStylePage()`, search-index `nav(…)` row with keywords, pass-down |
| `screens/settings/settings_tv_layout.dart` | `onOpenDebrifyTvStyle` param + Appearance row |
| `screens/magic_tv_screen.dart` | the branch in `build()` — and the deletion in §5 |

Registration is mechanical; the pattern is `iptv_style` end to end, and it is the
closest analogue because it is a *page* look rather than a shell look.

**No bridge, and no `notify:`.** `tv_home_style` and `tv_sidebar_style` need one
because the shell that reads them stays mounted. Tabs do not: `main.dart:2610`
builds `KeyedSubtree(key: ValueKey<int>(_selectedIndex), child: _buildPage(…))`
inside an `AnimatedSwitcher`, so switching tabs changes the key, disposes the old
page and gives the new one a fresh `initState`. Reaching the Presets picker means
leaving the Debrify TV tab, and coming back rebuilds it. Read the pref in
`initState` — this is exactly the reason `iptv_style_page.dart` documents for
having no bridge call of its own.

---

## 5. Delete the dead code first

`build()` calls `_buildTvGridLayout` on every device, which makes these
unreachable today:

`_buildChannelsTab` · `_buildChannelCard` · `_buildKeywordChip` ·
`_buildOptionChip` · `_buildEmptyChannelsState` · `_buildNoChannelResultsState`

**Delete by NAME, never by line range.** The dead methods span roughly
8924–9560, but that region is *interleaved with live code*:
`_showQuickPlayDialog` (`:9157`) and `_showGlobalSettingsDialog` (`:9299`) sit
between them and are called from the live grid layout (`:7963`, `:7735`). A
range delete takes Quick Play and Global Settings with it.

Delete the six in their own commit, before anything else. Otherwise this file
grows a *third* channel layout while still carrying a second one nobody can
reach.

---

## 6. Where the new layout lives

`magic_tv_screen.dart` is 11,259 lines. The Spotlight arm does **not** go inline.

```
lib/screens/debrify_tv/layouts/
  spotlight_layout.dart      // chooses the TV or phone arm
  spotlight_rail.dart        // the standing rail
  spotlight_stage.dart       // identity, stats, sample strip, actions
  spotlight_phone.dart       // list + channel sheet
```

They take a narrow view-model and a callback set from `_DebrifyTVScreenState`:

```dart
class DebrifyTvView {
  final List<DebrifyTvChannel> channels;
  final Set<String> favoriteIds;        // house spelling — matches _favoriteChannelIds
  final DebrifyTvChannelStats? stats;   // for the focused channel only
  final bool busy;
  final VoidCallback onQuickPlay, onAdd, onImport, onSettings;
  final void Function(DebrifyTvChannel) onWatch, onEdit, onShare, onDelete,
      onToggleFavorite;
  final void Function(DebrifyTvChannel) onChannelFocused;   // §7 — see below
  final void Function(DebrifyTvChannel, CachedTorrent) onWatchOne;   // §8
}
```

`onChannelFocused` is the seam §7 stands on: focus lives in the rail, *inside*
the layout, but the stats in `stats` are computed by the state. Without this
callback the state can never learn which channel to compute for. The rail calls
it on every focus move; the state debounces, computes, memoises, and rebuilds
with the new `stats`.

`onWatchOne` carries the channel as well as the pick, so the state can build
"the rest of the shuffled selection" (§8) from the right pool without relying
on its own focus tracking — an implicit coupling that would otherwise duplicate
what `onChannelFocused` already provides explicitly.

Nothing in that list is new *behaviour* except `onWatchOne`; `onChannelFocused`
is new plumbing for §7. Every other callback is an existing method on the state.

---

## 7. Stage data — and the one performance rule

New repository method returning, **per channel id**:

```dart
class DebrifyTvChannelStats {
  final int pooled;            // COUNT on tv_cached_torrents
  final int atYourQuality;     // _applyQualityFilterToCached over the pool
  final List<int> qualityMix;  // qualityTierForName, bucketed — shares the pass
  final List<String> deadKeywords;  // tv_keyword_stats where total_fetched = 0
  final DateTime? fetchedAt;   // tv_channel_cache_state
  final List<CachedTorrent> sample;
}
```

**The rule: the rail is cheap, the stage is lazy.**

- The rail draws `pooled` for every channel — that is **one `GROUP BY channel_id`
  count**, run once when the page loads.
- `atYourQuality` and `qualityMix` need a per-row name classify. Computed **only
  for the focused channel**, debounced on focus change, and memoised in a
  `Map<String, DebrifyTvChannelStats>` — a pool does not change while you are
  looking at it. Never classify all twelve channels on page load.

### The health pip, corrected

The mock's §2 table describes the amber pip as "thin at your quality". That would
force the expensive pass for every rail row. The pip resolves from cheap signals
only:

| Pip | Condition |
|---|---|
| red | cache status `failed`, or `pooled == 0` |
| amber | `pooled < kThinPoolThreshold`, **or** ≥ 1 dead keyword |
| green | otherwise |

`kThinPoolThreshold` is a named constant beside the pip resolver — start at
**25** and tune on a real panel in phase 8. It is a product number, not a
correctness one; nothing may branch on it except the pip colour.

The stage's status chip is where "only 11 at your quality" appears, because by
then the focused channel's pass has already run. Update the mock's §2 row to match
when this lands.

---

## 8. Play one title — the only new behaviour

OK on a sample plate plays *that* title. It exists because §3 of the mock forbids
promising what plays next: where a promise is impossible, offer a choice instead.

All five entry points already take a `List<Torrent>` and every one of them opens
with `if (cachedTorrents.isEmpty)`:

`_watchWithCachedTorrents` · `_watchAllDebridWithCachedTorrents` ·
`_watchTorboxWithCachedTorrents` · `_watchPikPakWithCachedTorrents` ·
`_watchPremiumizeWithCachedTorrents`

**Do not pass a single-element list.** The chosen torrent may not be cached at the
provider, and a one-item queue has nothing to fall back to — "play this one" would
then fail on exactly the picks where *Tune in* would have succeeded, which is the
worst possible way for a deliberate choice to behave.

Pass the chosen torrent **first, followed by the rest of the shuffled selection**.
It plays what you picked when it can, and falls through to the channel when it
cannot. Behaviour after that title ends is unchanged.

---

## 9. Phases

| # | Phase | Gate |
|---|---|---|
| 0 | Delete §5's dead code | `flutter analyze` clean; nothing renders differently |
| 1 | Pref + warm + generation 3 + Look keys + both bundles | `defaults_generation_test`, `app_looks_test`, `spotlight_look_test` all green with the new key |
| 2 | Picker page + Appearance rows + search index | Picker round-trips; Presets → Spotlight still reports **Spotlight**, not Custom |
| 3 | `DebrifyTvView` + the `build()` branch, Spotlight arm rendering channels only | `grid` identical **by construction** — the branch calls the existing `_buildTvGridLayout(bottomInset)` unchanged, never a re-implementation |
| 4 | Stage data + memoisation + pip | The rail-cheap/stage-lazy rule in §7 holds — verify no classify pass on page load |
| 5 | Phone arm | Television checked before any width breakpoint |
| 6 | `onWatchOne` | Plays the chosen title; an uncached pick falls through to the channel |
| 7 | Modal surfaces — see below | Each replaces its dialog only under `spotlight` |
| 8 | Fidelity pass against the mock, on a real panel | Band-by-band at 1:1 |

### Phase 7 in full — the surfaces phases 3–6 do not cover

The mock designs seven more screens, and none of them is part of "the branch in
`build()`". **Until each lands, the Spotlight arm reuses the grid-era dialog.**
They are already theme-aware, so nothing looks broken — just not yet redesigned.
Ship them in this order, cheapest first:

| Surface | Replaces | Note |
|---|---|---|
| Empty state | `_buildTvEmptyState` | Pure paint |
| Tuning | `ChannelCreationDialog` + `CachedLoadingDialog` | One surface for both; keep both call sites |
| Import | `ImportChannelsDialog` | Three destination cards; the community browser stays as it is |
| Share | the share `AlertDialog` | Overlay; the size/compression numbers stay |
| Quick Play | `_showQuickPlayDialog` | Two fixed bands + `TvKeyboardSlot` |
| Editor | `_openChannelDialog` | Same, and the headline TV-keyboard fix |
| Settings pane | `_showGlobalSettingsDialog` | **The expensive one.** Two builders are `_SettingsScope`-parameterised and shared with Quick Play — `_buildSettingsCard` (`:8672`) *and* `_providerChoiceChips` (`:1671`) — so re-hosting the pane as a page means splitting both shared builders rather than moving them |

## 10. Tests to update

- `test/theme/app_looks_test.dart` — bundle contents, `validate()`, `LookKeys.all`.
- `test/theme/spotlight_look_test.dart` — the Spotlight bundle gains a key.
- `test/defaults_generation_test.dart` — the existing nine still pass, plus the
  rows of §3.3's table as cases: a Spotlight install adopts `spotlight`;
  **a `legacy` install adopts `grid` and is NOT restyled**; a non-flagship theme
  adopts `grid`; **a Custom mix that kept `app_theme = 'spotlight'` adopts
  `spotlight`** (the proxy is the theme, not Look activity — §3.3); an
  explicitly written value survives untouched. Plus: running twice is a no-op,
  and a fresh install (gen 0 → 3 in one pass) ends on `spotlight` — that one
  covers the gen-1-writes-`app_theme`-first ordering the gen-3 block depends on.
- A Look round-trip test: apply Spotlight → `isActive` true; apply Classic →
  `isActive` true and `debrify_tv_style` is `grid`. This is the assertion that
  would have caught the Custom-flip.
- New: a coercion test for `kDebrifyTvStyles` (unknown → `grid`, both directions).

## 11. Deliberately not doing

- **Theme-time layout resolution.** §3.4.
- **A separate feature flag.** A picker value is already additive and reversible;
  every other layout in this app ships this way.
- **Per-channel style overrides.** No column, and it is a feature decision rather
  than a layout one.
- **Touching the playback flows.** §1.2. If the Spotlight arm needs something the
  state does not already expose, expose it — do not reimplement it.
