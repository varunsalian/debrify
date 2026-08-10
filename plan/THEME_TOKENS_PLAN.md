# Looks only, plus token-level control

**Goal.** A Look is the single top-level choice. Under it, an **Advanced** page
exposes the individual tokens, fully editable, on every theme except Classic.

## 1. What the code gives us, verified

* **Coverage is real.** 19 of 20 tabs are `SurfaceKind.themed`; the only frozen
  one is index 0, a deprecated inert slot. The remaining legacy freezes are the
  bootstrap overlays and the player, both deliberate. An edited token reaches
  the app.
* **Live apply works.** `AppThemeController` is a `ChangeNotifier`;
  `AppThemeScope` is an `InheritedTheme` whose `updateShouldNotify` is an
  identity check. Recompute + notify re-themes the running app. No preview
  surface is needed — the app is the preview.
* **Every editable theme has a `DetailTheme` core**, so colour overrides reach
  all of them through one narrow derivation.
* **Only `spotlight` has a `ThemeSpec`** of the seven Looks. The other six
  resolve a core and take `*.legacy` token groups. This is why resolution needs
  two arms rather than one.

**Classic (`legacy`) is not editable, by decision.** It already carries
`core: DetailThemes.signal` with every token group a no-op by construction, so
it is honestly the *unthemed* option rather than a gap in the feature.

## 2. Resolution

In `AppThemeController._recomputeSilently`:

```
overrides empty  → today's code path, untouched, byte for byte
_id == legacy    → today's code path (Classic is not editable)

core  = ThemeCoreResolver.resolve(_id, overrides)   // shared + memoized
core  = AppThemeAdapter.resolveCoreText(core, preset)

spec != null → overrides.applyToSpec(spec).buildWith(core)
spec == null → AppTheme.fromDetail(core, focus:, motion:, surface:, art:,
                                   light_:, idle:, wait:, sound:)
```

**`ThemeCoreResolver` is shared, not private to the controller.** Detail
layouts fetch their core straight from the registry
(`merged_series_detail_screen.dart:304`), so a core patched only inside
`AppThemeController` would leave every alternate detail page unthemed. One
memoized resolver, used by both.

**Patching a colour field is not enough.** The core's colours are
interdependent: `lightGround`, `tx2`/`tx3`, `calloutText`, the accent-button
inks and `stateGradient` are all derived, and `resolveCoreText` only recomputes
text from `tx` and `ground`. `ThemeSpec.toCore()` is the one place that derives
them together, so that derivation is extracted into a reusable palette
derivation and run whenever a colour is overridden — `stateGradient` especially,
which must be rebuilt or dropped when `state` changes rather than left pointing
at the old colour.

Colours are applied **before** `resolveCoreText`, because every derived surface
tone is computed from them and the preset must still resolve last.

Two arms, not a synthesised spec: a synthetic baseline would subtly restyle a
theme the moment you touched one unrelated knob, and "I changed the accent and
the shadows moved" is a bug report nobody can act on.

## 3. Overrides

Sparse `token id → value id`, one JSON pref. Sparse so a Look revision still
reaches anyone who has touched a knob; ids not values so a palette revision
cannot orphan a stored colour, and an unrecognised id falls back to the theme's
own value rather than painting something arbitrary.

| Section | Tokens | Arm |
| --- | --- | --- |
| Colour | accent, focus, state, callout | core |
| Ground | ground, sunken/pane, raised/panel, ink | core |
| Shape | radius, pillRadius | core |
| Type | displayFont, bodyFont | core, BOTH arms |
| Focus | focusExpression | both |
| Motion | motion character, entrance, idle | both |
| Surfaces | separation, scrim | both |
| Artwork | frame, grade, reactiveRoom, artworkAccent | both |
| Texture | grain, sheen, vignette, bloom | both |
| Feedback | feedback character, skeleton | both |

Shape and type go through the core on **both** arms: `ThemeSpec.buildWith` uses
the core it is handed unchanged, and `ShapeTokens`/`TypeTokens` are derived from
it. Radius means `radius` + `radiusSm` + `radiusImg`; pill radius means
`radiusBtn` + `radiusCast` — matching what `ThemeSpec.toCore` already does, or
the corners disagree with each other.

Texture is available on both arms too, not spec-only: grain is core-backed,
sheen lives in `SurfaceTokens`, and vignette/bloom in `LightTokens`, all of
which `fromDetail` accepts. One ordering trap — `MotionTokens.fromDetail`
derives its tempo from grain, so the non-spec arm must take its motion baseline
BEFORE grain is changed, or editing texture silently retimes the app.

## 4. Colour freedom, and the one guard

Ground and ink are freely editable, as asked. They are also the legibility
system — every surface tone derives from them — so the guard is **recovery, not
prevention**: per-section reset, a global reset, and both reachable without
being able to read the screen (fixed position, first row of the page).

## 5. UI

One descriptor list drives everything: a generic option page for enums, a swatch
grid for colours, inline steppers for scalars. Twenty hand-written rows would be
twenty chances to get DPAD wrong.

## 6. Phases

1. **Foundation** — override model, `ThemeSpec.copyWith`, narrow `DetailTheme`
   derivations, storage, controller resolution, live apply. Tests.
2. **The page** — Advanced under Appearance, all sections, resets. Looks page
   shows "modified" and applying a Look clears overrides.
3. **Retirement** — App Theme and Details Theme entries leave Appearance.
   `effectiveDetailTheme` moves out of `detail_theme_page.dart` first (two
   production files import it), the retired-page test goes, and
   `shape_manifest_test` is updated. Anyone on a theme no Look names is left
   exactly where they are and reads as Custom — nothing is rewritten under them.

## 7. Risks

| Risk | Handling |
| --- | --- |
| Unreadable ground/ink | recovery, not prevention (§4) |
| Baseline shift on first override | two arms, no synthetic spec (§2) |
| Palette revision orphaning colours | store swatch ids; unknown → theme's own value |
| Theme snapshot tests | overrides empty by default; assert that explicitly |
| `detail_theme_page` exports runtime policy | moved before the page is retired (§6.3) |
| Detail pages bypassing the override | shared `ThemeCoreResolver` (§2) |
| Grain retiming motion on the non-spec arm | motion baseline captured first (§3) |

## 8. Tests

- Empty overrides resolve identically to today, on both arms.
- An override changes the built theme; clearing restores the Look's value.
- Unknown swatch and unknown enum name both fall back rather than throw.
- Round trip through the stored JSON.
- Malformed JSON degrades to none.
- Applying a Look clears overrides.
- Classic ignores overrides entirely.
- A colour override rederives its dependents: overriding `ground` flips
  `lightGround` and moves `tx2`/`tx3`; overriding `state` does not leave a
  stale `stateGradient`.
- An alternate detail layout sees the overridden core, not the registry's.


---

## 9. What was built (2026-08-10)

All three phases. Uncommitted. Four codex rounds on the plan, three on phase 1,
two on phase 2, three on the whole.

### Deviations, and why

**Polarity became ONE decision.** The plan had ground, pane, fill and ink as
four free choices. They cannot be: a light page over a dark sheet has no single
ink that reads on both, and every fix for one broke the other. The Panel and
Fill knobs are gone; the ground sets polarity and pane/rail derive from it. Hue
stays free. This is the one place the "fully flexible" brief was narrowed, and
it was narrowed because the alternative was combinations that are unsatisfiable
rather than merely ugly.

**A 3:1 legibility floor was added, and it overrides explicit choices.** Ink
that fails against the ground or pane is moved to whichever pole reads. It is
re-applied inside `withText`, which runs last, because the text-brightness
preset blends toward the ground and could otherwise undo it. A cursor gets the
same treatment: chosen, else authored, else a readable pole.

**Surfaces and ink got their own palettes.** The 50-swatch set is a palette of
MARKS — everything in it is above 5% luminance so it can be found on a dark
ground, which means it contained nothing usable as a background. `grounds` runs
near-black to off-white; `inks` is five entries, because ink is a legibility
decision rather than a taste one.

**The reset row is painted in fixed colours** (`0xFF101012` on `0xFFF2F2F4`) and
sits first on the page. The guard on this feature is recovery, not prevention,
and a themed escape hatch would be invisible in exactly the case it exists for.

**Advanced lives under Looks**, not as a third Appearance row — it is what Looks
is an alternative to, and putting it there avoided duplicating navigation across
the phone and TV layouts.

### Known, and deliberate

* Classic is not editable. It is a hand-built theme whose token groups are
  no-ops; that is what makes it the honest *unthemed* option.
* Light grounds are now reachable, and `kDetailThemesShipped` withholds two
  themes precisely because screens with hardcoded light-on-light literals do not
  follow a pale ground. The floor keeps TEXT readable; it cannot fix a literal
  that never consulted the token layer. **Anyone choosing a light ground will
  meet that bug.**
* `detail_theme_page.dart` still exists and still re-exports the policy that
  moved to `shipped_themes.dart`. Only its Appearance entry is gone.

### Verified

Analyze clean, baseline 9/9 by name, 438 theme tests. **Not verified:** anything
about how it looks or feels on a panel, and no DPAD walk of the new pages on
real hardware.
