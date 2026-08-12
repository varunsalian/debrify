# First Run — onboarding, rebuilt as a stage

Replace the first-run dialog (`lib/widgets/initial_setup_flow.dart`, 4906 lines,
one `State` class) with a full-screen **setup stage** in the Spotlight idiom, fix
the three UX failures that make it painful on a television, and make the same
flow work at every width.

The mock is `design/mockups/onboarding_mockup/index.html` — playable, drawn at
1920×1080. **Every number in this document is logical (÷2)** unless it says
otherwise.

> **Revised twice against codex review.** Round 1 (11 P1, 3 P2) killed the
> per-provider phone-send design, resized the keyboard band, replaced the
> standalone keyboard host with a slot on the existing field, corrected three
> theme/focus APIs, and moved characterisation tests to the front. Round 2
> (8 P1, 1 P2) added a **Back-ownership contract**, made the keyboard band
> **measured rather than declared**, gave grouping/paste a single
> canonicalisation path, told the truth about what the import screen can
> actually observe, fixed the responsive table (**television is 960×540
> logical — width alone must not choose the layout**), and corrected the
> Phase 0a contract. §12 records every finding and its fate, so nothing
> rejected gets re-proposed.

---

## 1. Non-negotiables

1. **The mock is the spec for layout, copy and DPAD — not for subsystems it only
   draws.** The mock's keyboard is a *picture of* `TvKeyboardPanel`. Ship the
   real panel with its real key grid; do not build a second keyboard to match a
   drawing.
2. **The returning-user path cannot move.** `AppInitializer._showOnboarding`
   keeps calling `InitialSetupFlow.show(context)` and keeps getting a
   `Future<bool>` meaning "something was configured". Splash, bootstrap freeze,
   migrations and the ident are untouched.
3. **Additive and reversible.** Everything lands behind
   `StorageService.onboardingV2`, **default off on every build until Phase 4
   completes the state machine** (§8). The old widget stays compilable and
   reachable until Phase 5 deletes it.
4. **DPAD before paint.** Every screen declares its focus grid and landing node
   in one table. No geometric traversal, no wrapping, LEFT at column 0 parks on
   Back and RIGHT returns. **One declared exception:** inside the keyboard the
   shipped controller wraps horizontally on purpose — "long reaches across a row
   are one press, not nine" (`tv_keyboard.dart:279-292`). That routing is not
   touched, so Back is reached from the keyboard by travelling **UP** out of it,
   never by LEFT (§6a).
5. **The field band and the keyboard band never overlap.** Siblings with their
   own heights, sized against the panel's *measured* minimum (§5.1). A widget
   test pins it.
6. **Nothing new on the wire.** No new `ConfigCommand`, no sender-side change,
   no protocol version. This constraint is what forced the phone-entry redesign
   in §5.4 — read it before proposing anything cleverer.
7. **Every step reversible and skippable, and the flow can be left.**
8. **TV cost budget.** Four separate rules, since the list reads as one
   sentence otherwise: (a) no full-screen `Opacity` cross-fades; (b) **wrap**
   anything that animates on focus in a `RepaintBoundary` — required, not
   forbidden; (c) no `X.of(context)` inside an animation callback; (d) alpha
   baked into colours.

---

## 2. What is actually wrong today

Ranked by how much a real user feels it. Each row is the reason a phase exists.

| # | Failure | Where |
|---|---|---|
| 1 | **The TV keyboard lands on top of the API-key field.** The panel is a root-overlay at `bottom:16`; the field is one line inside a 560-wide dialog inside a `SingleChildScrollView`. `_beginEdit`'s `Scrollable.ensureVisible(alignment:0.2)` is the existing mitigation and cannot win — the dialog is centred and usually has no scroll extent to give. | `tv_text_field.dart:420-473`, `initial_setup_flow.dart:2164` |
| 2 | **You type 40 characters you cannot read.** Body-size text, no grouping, no count, no live validation; the error appears only after you commit. | `_buildIntegrationStep` |
| 3 | **Typing on a remote is the only way in.** | ditto |
| 4 | **No progress, no orientation.** | whole flow |
| 5 | **No way back** once you leave the welcome step — engines, Trakt and Simkl are one-way. | `_goBack:3334` |
| 6 | **No way out.** `PopScope(canPop:false)` + `barrierDismissible:false`. | `show():45-55` |
| 7 | **Off-theme.** A slate `#0F172A→#1F2937` dialog frozen under `LegacyThemeBoundary`, beside a Spotlight Home. | `show():53` |
| 8 | **Trakt and Simkl are ~800 near-identical lines** for one decision. | `2451-3277` |
| 9 | **The import guide slides out from under the reader** every 5 s, wraps forever, no failure copy. | `_restartImportAutoAdvance:1126` |
| 10 | **Engines are bare names** in a 280px scroller, all pre-ticked — a choice with no information to make it with. | `_buildEngineSelectionStep:2249` |
| 11 | **The flow just pops.** No confirmation of what connected or what was skipped. | `_finishOnboarding:3921` |

> **Correction, recorded so it cannot come back.** An earlier draft said the
> engine step pre-selects "all 18". The catalogue is fetched live from
> `gitlab.com/mediacontent/search-engines → torrents/metadata.yaml` and holds
> **8** today. Nothing in the repo pins that number, so **no UI may hardcode
> it** — the grid reflows to whatever the manifest returns.

---

## 3. Architecture

### 3.1 A route, not a dialog

`InitialSetupFlow.show` keeps its signature and its two side effects (clearing
focus, restoring `parentFocusScope.canRequestFocus`), and internally pushes an
opaque **`PageRouteBuilder` on the root navigator**:

- opaque, no barrier → no 0.85 scrim, no inset maths, no 560px clamp;
- `maintainState: true`; transition = 220 ms fade off-TV, **cut** on TV (§1.8);
- `Navigator.pop(value)` returns the same bool, so `_showOnboarding` is unchanged;
- the remote-config restart (`pushAndRemoveUntil`, `main.dart:516`) still removes
  it, and `_showOnboarding`'s `if (!mounted) return` still guards the write after.

**Not `FrozenLegacyPageRoute`.** It exists but always injects
`LegacyThemeBoundary` (`app_surfaces.dart:161-167`) — the exact thing §3.2 is
undoing — and it cannot carry a custom transition.

**No surface-classification problem exists.** `AppSurfaceState.active`
short-circuits to `frozen` while `_bootstrapActive` (`app_surfaces.dart:77`), and
`publishBootstrap(false)` runs *after* `show()` returns (`app_initializer.dart:292,315`),
by which time the route has popped. A pushed `PageRouteBuilder` is tracked as a
page route (`app_surfaces.dart:99`) but never gets to decide anything.
*Route-stack tests still cover normal pop and remote restart (§9.7).*

### 3.2 Theme: scope it to Spotlight — **both halves**

Onboarding is currently an excluded surface under `LegacyThemeBoundary`
(`show():53`). Replace that with a fixed Spotlight identity built once:

```dart
// memoised in a static — computed at most once per process
final core  = AppThemeAdapter.resolveCoreText(          // app_theme_adapter.dart:294
                ThemeCoreResolver.resolve('spotlight', ThemeOverrides.none), // :28
                TextBrightnessController.current);      // text_brightness.dart:68
final theme = PremiumLooks.spotlight.buildWith(core);   // premium_looks.dart:213, theme_spec.dart:357
final data  = AppThemeAdapter.themed(theme, TextBrightnessController.current); // :316
```

and wrap the stage in **`Theme(data: data, child: AppThemeScope(theme: theme, …))`**.

**Both are required.** `AppThemeScope` supplies only `AppTheme` tokens
(`app_theme_scope.dart:31`) — it does not touch `Theme.of`. Without the `Theme`
above it, Material widgets inherit the legacy `ThemeData` (under a boundary) or,
on a normal route, whatever theme a half-configured install happens to have
selected. Either is a bug.

Why scope at all rather than hand-paint a palette: `ParallaxFocus` reads
`AppThemeScope.of(context)` and returns its child verbatim unless the expression
is `parallax` (`parallax_focus.dart:124`). Under the legacy freeze the mock's
entire focus mechanic is a silent no-op. Scoping is what makes it real without
one line of new focus code.

**Still to decide in Phase 1:** system bars and global feedback stay
bootstrap-frozen (the ident owns them until the splash lifts) — confirm on device
that a themed subtree under a frozen surface does not fight `system_bars.dart`.

### 3.3 One state machine, declared

Replace `int _stepIndex` + `_engineStepIndex = _flow.length + 1` arithmetic
(`3682-3692`) with

```dart
enum OnboardStep { mode, services, key, engines, trackers, importing, done }
```

plus a per-step record `{ landingNode, canSkip, canBack, ladderIndex }`. The
per-provider cursor lives *inside* the `key` step (`_flow`, `_flowIndex`), not
spliced into a global index. This is what kills failure #5: Back becomes a
property of the table rather than of one branch.

### 3.4 Back has exactly one owner

The dialog blocked system Back outright (`PopScope(canPop:false)`,
`initial_setup_flow.dart:601`). A pushed route does not, so Back becomes real
and needs a contract — and it must survive **nested** `PopScope`s, because
`TvTextField` installs its own to keep Back from popping the route while the
keyboard is up (`tv_text_field.dart:1130-1140`, with `_popGuard` holding it
armed across the whole press). Flutter notifies **every** registered
`PopEntry` on a blocked pop, so a naïve stage-level handler would fire on the
same press that closed the keyboard, and step *back* as well.

| State | Back does | Owner |
|---|---|---|
| keyboard session open | closes the keyboard only | the **field's** `PopScope`, unchanged |
| provider n>1 | previous provider | stage, only when no session is open |
| provider 1 | services | stage |
| services / engines / trackers | previous step | stage |
| importing | mode | stage |
| **mode** | `_leave()` — queue the banner, pop `false` | stage |

**The guard cannot be "is a panel attached".** The field arms its 300 ms
`_popGuard` **before** calling `_endEdit` — `_armPopGuard(); _endEdit();`,
"before `_endEdit` — same rebuild registers it" (`tv_text_field.dart:843-849`,
window at `:264-275`). Under the slot, `_endEdit` detaches the panel, so by the
time Android re-delivers that same press through the navigation channel the
notifier is already null, the stage's guard is open, and the stage steps back
on the press that only closed the keyboard. That is the exact double-dispatch
the field's `_popGuard` exists to absorb, reproduced one level up.

So the session carries the ownership signal, and it **outlives the detach**:

```dart
class TvKeyboardSession {
  /// True while a panel is attached AND for the same guard window the field
  /// uses, so a pop belonging to the closing press is never the stage's.
  bool get ownsBack;
  void holdBack();   // called from _armPopGuard whenever a slot is attached
}
```

The stage's `onPopInvokedWithResult` returns immediately while
`session.ownsBack`. §9.3 tests the **sequence**, not the state: physical
Back-down with the keyboard open, then `handlePopRoute` within 300 ms, and
assert the step did not change — a test that only pops while the panel is
attached passes against the broken version.

### 3.5 File layout

```
lib/widgets/onboarding/
  onboarding_flow.dart        // entry, route, state machine
  onboarding_stage.dart       // rail + ladder + act + footer shell
  onboarding_focus.dart       // grid model + landing table
  onboarding_theme.dart       // the memoised Spotlight pair (§3.2)
  steps/{mode,services,key,engines,trackers,import,done}_step.dart
  controllers/tracker_auth_controller.dart   // Trakt device-code + Simkl PIN
```

---

## 4. Geometry (logical; mock ÷2)

| Band | Value |
|---|---|
| Page gutter | 42 |
| Rail width | 300 (collapses to 63 on the key step) |
| Rail top | 48 · Back disc 33, then 22 gap |
| Eyebrow | 10 mono, .22em, `white .42` |
| Title | 31/1.06 w700, −0.7 tracking |
| Subtitle | 12.5/1.46, `white .6`, max 34ch |
| Ladder | bottom 44; row 11, dot 11, gap 9 |
| Act column | left 384, right 42, top 48, bottom 107 |
| Footer row | bottom 44, right-aligned; count on the left |
| Card radius | 11 · hairline `white .07` |
| Primary pill | h36 r18, pad 0/21, 12.5 w600 — focus = solid white on black |
| Ghost | 11.5 `white .55`; focus fills `white .14` |

**Focus.** `FocusExpression.parallax` comes from the scope; sites wrap in
`ParallaxFocus` **directly** and pass a real shape:

| Site | `ParallaxShape` |
|---|---|
| mode row, service card, engine tile, tracker card | `sourceCard` (1.10) |
| pills, ghosts, method chips | `pill` (1.06) |

`FocusExpressionBox` is **not** used here: it has no shape argument and falls
through to `ParallaxFocus`'s default poster scale (`focus_expression.dart:82`),
and unlike `ParallaxFocus` it is not a no-op under other expressions — it
implements ring/invert/flood/underline/scale/lift paths of its own
(`focus_expression.dart:67-99`). `ParallaxShape.card` **does not exist**; the
values are poster, landscape, sourceCard, episodeStill, castCircle, pill
(`parallax_focus.dart:15-20`).

---

## 5. The key step — the whole point of this exercise

### 5.1 Bands, sized against the real panel

`TvKeyboardController.rows` is always four key rows **plus** the action row
(`tv_keyboard.dart:245`). A keycap is 40 high with 2 margin all round = 44
(`:623`), and the panel adds 10 padding top and bottom (`:387`):

```
5 × 44 + 20 = 240 minimum
```

and the notice bar is inserted **above all five rows** in the same `Column`
(`:409-417`), costing 6 margin + 14 padding + a 15px icon line ≈ 35 more.
So the panel is ~240 at rest and ~275 with a notice — **and more under text
scaling**, which no constant can anticipate.

**Therefore the band is measured, not declared.** The screen is

```
Column(children: [
  Expanded(child: fieldBand),          // takes whatever is left
  ConstrainedBox(minHeight: 275, child: keyboardBand),  // sizes to the panel
])
```

The panel's intrinsic height wins; the field band absorbs the remainder. The
no-overlap invariant then holds at *any* panel height — notice bar, text
scaling, a future sixth row — because it is a property of the `Column`, not of
a number someone got right once.

| Band | Rule |
|---|---|
| Rail | Back only, collapsed to 63 |
| Field band | `Expanded`. Provider mark + name + "service n of m", the method chips, the **echo**, one status line. Its own content is `MainAxisSize.min` and top-anchored, so shrinking is graceful. |
| Keyboard band | Bottom-anchored, sizes to `TvKeyboardPanel`, floor 275 |

The mock's 272→540 is the *design* figure that the fidelity pass checks at
default text scale; it is not the mechanism.

Panel `maxWidth` is 620 (`:386`) against an 876-wide act column; raising it is
**optional polish**, not a fix, and if taken it is an additive parameter
defaulting to 620.

### 5.2 `TvKeyboardSlot` — move the panel, keep the field

**Rejected:** a standalone `TvKeyboardHost` that renders the panel from a bare
`Focus`. `controller.handleKey` consumes only arrows and activate — printable
characters are deliberately left to the caller (`tv_keyboard.dart:250`) — because
the real text input is the `TextField` underneath, which on Android keeps its
input connection with `TextInputType.none` **precisely so a paired Bluetooth
keyboard can still type** (`tv_text_field.dart:1089-1104`; tvOS trades that away
with `readOnly` and says so). A host without a field silently drops hardware
keyboards, voice (`onVoice`/`onVoiceStop`), the system-IME hand-off — which is
in the action row on every non-tvOS platform (`:99`) — and the paste notices.

**Adopted:** keep `TvTextField` exactly as it is and change only *where its panel
is drawn*.

```dart
/// Ancestor marker. A field that begins an edit session and finds one of these
/// publishes its controller here instead of inserting a root OverlayEntry.
class TvKeyboardSlot extends InheritedWidget {
  final TvKeyboardSession session;
}

class TvKeyboardSession {
  final ValueNotifier<TvKeyboardController?> panel;
  /// Identity-checked: a detach for a controller that is no longer the
  /// attached one is a no-op, so a late teardown cannot blank a newer session.
  void attach(TvKeyboardController c);
  void detach(TvKeyboardController c);
}
```

**Teardown is the whole risk, and there are three exits, not one:**

| Exit | Today | Under the slot |
|---|---|---|
| `_endEdit` (`:476`) | `_removeOverlay()` | `session.detach(_kb!)` |
| `_switchToSystemIme` (`:496`) | **bypasses `_endEdit`** — removes the overlay, disposes `_kb`, nulls it | must `detach` first, or the notifier holds a **disposed** controller and the panel stays mounted |
| `dispose` (`:353-355`) | `_removeOverlay(); _kb?.dispose();` | `detach` on a **cached** slot reference — `dependOnInheritedWidgetOfExactType` is illegal in `dispose` — and the notify is deferred to a post-frame callback so it never wakes a sibling `ValueListenableBuilder` mid-teardown |

Other rules:

- `_beginEdit`: slot present → attach; absent → today's `OverlayEntry` path,
  byte-identical.
- The key screen renders `ValueListenableBuilder(session.panel) →
  TvKeyboardPanel(...)` in its keyboard band with Spotlight
  `ground/ink/accent/inkOnAccent`.
- `Scrollable.ensureVisible` (`:466`) is skipped when a slot is present — there
  is nothing to scroll out from under.
- **No `captureAppThemes`.** That helper exists for bare overlays that inherit
  nothing (`overlay_theme.dart:6`); a slotted panel is an ordinary child of the
  page and inherits the Spotlight pair already.

Everything else — shift, page, **voice**, the IME hand-off, paste, notices,
arrow routing, the Back `PopScope` — is untouched and therefore free. Voice in
particular is a deliberate keep (§10): the mic key stays in the action row on
the key step, and it works only because the field survives — the rejected
standalone host would have dropped it along with `onVoice`/`onVoiceStop`.

### 5.3 The echo

The echo **is** the `TvTextField`, restyled: 19 mono, 2.5 tracking, its own
caret, no border. Not a read-only `Text` (§5.2).

- **Grouping in 4s** goes through **one canonicalisation path**, because the
  naïve version corrupts the provisioning prefix: submission detects `nonav:`
  *before* any whitespace handling (`3562-3570`), so a formatter grouping the
  whole string produces `nona v:…` and offsets every group after it.

  ```dart
  typedef KeyParse = ({String key, bool hideFromNav});
  KeyParse parseKey(String raw);   // strips grouping, lifts nonav:, returns BOTH
  String   group(String payload);  // 4s, payload only
  ```

  **`parseKey` returns two things, not one.** `nonav:` is not decoration — it
  is a provisioning side effect: the prefix is stripped *and* the provider is
  hidden from navigation afterwards (`initial_setup_flow.dart:3566-3570` →
  `3612-3622`). A helper that returned only the clean key would pass a
  validation test while silently dropping that behaviour. The formatter groups
  the **payload only** and never touches the prefix; `_submitCurrent` replaces
  its ad-hoc trim with `parseKey` and keeps using `hideFromNav` exactly as it
  does today.
- **Paste has one entry point too.** The keyboard's paste key already routes
  through `_insertText` and therefore the formatter (`tv_text_field.dart:731`),
  but that is private — the new Paste chip cannot reach it, and assigning
  `controller.text` would bypass both the formatters and `onChanged`.
  `TvTextFieldState` is already public (`:236`), so it gains a public
  `insertText(String)` that the chip calls through a `GlobalKey`. The chip and
  the key then share one path.
- **Never masked.** A token is not a password and masking defeats the entire
  purpose of making it readable. Recorded so it is not re-proposed.
- **Length is per provider, nullable.** Only Real-Debrid documents 40 characters
  (`98-106`); Torbox, Premiumize and AllDebrid deliberately claim nothing
  (`113,143,158`) and submission accepts any non-empty string, leaving the
  verdict to the server (`3572`). So `_IntegrationMeta` gains
  `final int? keyLength`, the status line says `n of 40` only when it is known
  and `n characters` otherwise, and the echo scrolls horizontally rather than
  assuming it fits.

| State | Copy |
|---|---|
| empty | Nothing entered yet |
| partial, known length | `n of 40` |
| partial, unknown length | `n characters` |
| complete/non-empty | Press Connect |
| validating | Checking with Real-Debrid… |
| ok | Connected · Premium, 245 days left |
| fail | That key didn't work — check for a missing character |

### 5.4 Ways in — and why there are two, not three

| Method | Mechanism | New code |
|---|---|---|
| **Type** | §5.2 | the slot |
| **Paste** | `Clipboard.getData` on step entry; if it plausibly matches this provider, the chip is offered and is the **landing focus** | trivial |

**"Send just this key from my phone" is cut.** It cannot be built under §1.6.
`RemoteConfigExport` sends `ConfigCommand.complete` after any successful batch
(`remote_config_export.dart:594-598`), and on a device that has not completed
setup the receiver marks setup complete and calls the restart callback
(`remote_command_router.dart:676-697` → `main.dart:516`), which replaces the
whole navigator stack. A phone send therefore **ends onboarding by design**; it
cannot advance one provider. Worse, `dispatchCommand` fires `addHandler`
listeners *before* `_handleConfigCommand` runs, and validation/persistence
happen in an unawaited async path afterwards (`:246-276`, `:416`, `:472`) — so a
listener cannot tell a good key from a bad one anyway.

What ships instead: the key step's third chip is **"Send everything from my
phone"**, and it navigates to the `importing` step. That is the honest
description of what the wire does, it costs nothing, and it is a better answer
for a user who has Debrify on a phone already.

**Deferred, with its price stated:** per-provider send needs (a) a
session-scoped receive mode that suppresses the `complete` restart, and (b) a
result event published *after* each config handler resolves, carrying
provider + success + error. That is router work, it is not in this plan, and it
must not be smuggled into a phase.

Phone/desktop: Type and Paste as a segmented control; the CTA sits in a
`viewInsets`-padded bar so it rides the soft keyboard instead of hiding under it.

---

## 6. Screens

| Step | Content | Grid | Landing | Skip |
|---|---|---|---|---|
| **mode** | set up here · bring it from another device · *Skip — I'll do this later* | 3×1 | row 0 | n/a |
| **services** | 5 provider cards + "None of these", each with a one-line "what this is" | 2×3 + footer | first card | "I don't have any" → engines |
| **key** | §5, repeated per selected provider. PikPak keeps its 2-field variant and its folder-restriction dialog verbatim | §5 | Paste chip if the clipboard matches, else the field | per provider |
| **engines** | one tile per manifest engine, all on, one-line description; "Turn all off" | ⌈n/4⌉×4 + footer | first tile | Turn all off → Continue |
| **trackers** | Trakt and Simkl side by side; activating one turns **that card** into the code panel in place, the other dims | 1×2 + footer | Trakt | "Skip both" |
| **importing** | static 3-item checklist + live panel (§6b) | footer only | "Set up here instead" | — |
| **done** | what connected / what was skipped / where to change it | 1×1 | Start watching | — |

### 6a Leaving the keyboard

**Neither LEFT nor UP escapes it, and neither is made to.** LEFT wraps by design
(§1.4). UP is swallowed too: `_KbNavAction.invoke` forwards every arrow to
`controller.nav` and consumes it unconditionally (`tv_text_field.dart:163-170`),
and `nav` clamps vertically at row 0 (`tv_keyboard.dart:279-292`). An earlier
draft claimed a top-edge exit; it does not exist, and adding one would be a
change to shipped keyboard routing that §5.2 promises not to make.

**The exit is Back** — the shipped idiom, already correct: Back closes the panel
and returns focus to the field shell (`:843-849`). From the shell, LEFT calls
`widget.onLeftArrow` **unconditionally** (`_handleShellKey`, `:868-877`), so the
key step simply passes `onLeftArrow: () => focusBack()` and the exit works at
any caret position.

*(`_EdgeLeftAction`'s "caret at position 0" condition — `:206-219` — governs a
different mode: the plain/passthrough `TextField` path (`:986`, `:1069`), not
the TV shell. An earlier draft applied it to the shell and concluded mid-text
LEFT "falls through to the page grid". That was false.)* §9.3 still tests LEFT
from the shell at the start **and** mid-text, because the two used to be
claimed to differ.

### 6b What the import screen may claim

Only what it can actually observe. `dispatchCommand` calls `addHandler`
listeners **before** `_handleConfigCommand` runs (`remote_command_router.dart:246-276`),
validation and persistence are unawaited after that (`:352`, `:416`, `:472`),
the router's success/failure lists are private snackbar state, and **the sender
transmits no item total** — so a determinate progress bar would be a fiction
and a per-item ✓ would be a claim the receiver has not yet earned.

The panel therefore shows: **connection state**, **the count of items
received**, the name of the last one, and an **indeterminate "applying…"**
until `config/complete` arrives. Failure copy covers the one failure the UI can
see — the connection dropping — and says the transfer resumes on reconnect.
The mock's determinate bar is replaced by an indeterminate one; the mock is
wrong here and this paragraph wins.

*If truthful per-item results are wanted later*, the router needs an internal
post-resolution result stream (provider, ok/failed, error). That is the same
prerequisite as per-provider phone send (§5.4) and is deferred with it — no
wire change, but real router work.

**Engine descriptions come from `metadata.yaml`** — the catalogue owns its own
copy, decided 2026-08-12. Three parts, and only the first is in this repo:

1. **Parse it.** `_parseMetadata` hardcodes `description: null` behind a comment
   that says these "can be added to metadata.yaml in the future if needed"
   (`remote_engine_manager.dart:191-198`). Read `description` off each entry
   into the `RemoteEngineInfo.description` field, which already exists (`:12`)
   and is currently never populated by anything.
2. **Author it upstream** — one `description:` line per entry in
   `gitlab.com/mediacontent/search-engines → torrents/metadata.yaml`, beside
   the existing `name:` and `path:`.
3. **Fall back to the name alone** when it is absent. Not optional: the
   catalogue is fetched live and may be older than the app, entries can be added
   without copy, and the **legacy fallback parser cannot supply one at all** —
   `_fetchEngineInfo` reads only `display_name` and `icon` off each engine's own
   YAML (`:279-297`), and those files carry no description today.

The per-engine YAMLs are **not** the source: using them would mean downloading
all eight files to draw one screen, where the catalogue is a single fetch.

The blurbs in the mock are placeholders written by me and are not product copy —
they get a pass before they go upstream.

**Leave and skip are the same thing, deliberately.** Both mark
`initial_setup_complete_v1` and both queue the one-time Home banner → Settings ›
Services. `AppInitializer` marks setup complete after *every* normal return
regardless of the popped bool (`app_initializer.dart:292-296`), so a "leave"
that popped `false` would persist identically; inventing a third state would
mean changing the caller, which §1.2 forbids. System Back on the mode step, the
Skip row, and a completed run all land in the same place, and §9.4 tests that.

---

## 7. Responsive

**Television wins over geometry, and it is checked first.** A 1920×1080 panel is
a **960×540 logical** surface — which falls inside the "tablet" band below, so a
width-only rule would send the television to the header layout. The repo already
settles this exact question the same way for detail pages
(`resolveDetailSize(isTelevision: true, size: Size(960,540)) → DetailSize.tv`,
`test/detail_page_layouts_test.dart:11-16`).

```dart
OnboardLayout resolve({required bool isTelevision, required Size size}) =>
    isTelevision ? OnboardLayout.stage : _byWidth(size.width);
```

| Case | Layout |
|---|---|
| `isTelevision` | **stage** — at any size |
| width < 600 | one column; segmented progress; sticky CTA above `viewInsets` |
| 600–1000 | rail becomes a header; grids 2-up; footer bottom-anchored |
| > 1000 | stage, with hover = the focus expression at 60 % amplitude |

`PlatformUtil.isTelevision` still selects the **input model** (DPAD + in-app
keyboard) independently. TV widget tests run at **960×540 logical**; a test that
wants 1920 physical pixels sets `devicePixelRatio: 2`, it does not set a
1920-logical surface.

---

## 8. Phases

One deliverable each, left uncommitted for testing before the next begins.
**The flag stays off until Phase 4 lands** — `AppInitializer` has a single
blocking `await` (`app_initializer.dart:289`) and cannot hand a half-built V2
back to V1 mid-flow.

| # | Deliverable | Files |
|---|---|---|
| **0a** | **Characterisation tests against the CURRENT widget — pinning what it does, not what V2 will do.** There is no done screen: the build branches among mode / import / welcome / engines / trackers / integrations (`698`) and the flow ends by popping (`3921`), so 0a pins **trackers → pop**. It also pins the two absences: system Back is **blocked** (`PopScope(canPop:false)`, `601`) and `_goBack` exists **only** for provider traversal (`3334`). Plus: poll cancellation on dispose, phone-import restart, validation success/failure, and both return values. Done-screen and all-step-Back assertions belong to the Phase 4 V2 suite. | `test/onboarding/legacy_flow_test.dart` |
| **0b** | **Extraction.** Tracker auth machinery → `TrackerAuthController` with explicit `dispose`; steps → widgets. Not a file move: timers, focus nodes and their disposal are fields of one `State` (`283`, `325`, `528-571`) and private members are not importable. **Decision: extract controllers with public APIs, not `part of`** — `part` would keep the god-object alive under a new name. 0a must be green before and after. | `lib/widgets/onboarding/**` |
| **1** | Stage shell: route (§3.1), Spotlight pair (§3.2), rail + ladder + act + footer, focus grid, **mode** + **services**. Flag off. | shell files, `storage_service` |
| **2** | **The key step**: `TvKeyboardSlot`, restyled echo, formatter, status machine, per-provider length metadata, Paste, PikPak variant. | `tv_text_field.dart`, `tv_keyboard.dart`, `key_step.dart` |
| **3** | Engines grid from the live manifest; **parse `description` in `_parseMetadata`** (§6) with the name-only fallback; trackers merged onto one screen using `TrackerAuthController`. Authoring the upstream `description:` lines is a parallel content task — the fallback means Phase 3 is not blocked on it. | `remote_engine_manager.dart`, `engines_step`, `trackers_step` |
| **4** | Import rebuilt (static checklist, honest live panel §6b); **`RemoteControlState.ensureReceiverMode(name)`** — serialised and idempotent — with both `AppInitializer._startTvListenerEarly` and the import step routed through it (§8a); done step; skip/leave semantics + Settings banner; the §3.4 Back contract. **Flag may now default on in debug.** | `import_step`, `done_step`, `remote_control_state.dart`, `app_initializer.dart`, `settings_screen` |
| **5** | Phone/tablet layouts, band-by-band fidelity pass against the mock, spec test, flag on in release, delete the old widget. | all, `test/**` |

### 8a The receiver race is real and is fixed here, not "accepted"

`AppInitializer` fires `_startTvListenerEarly()` unawaited (`app_initializer.dart:166,172`);
the import step independently checks `isTv` and may call `switchToReceiverMode`
(`initial_setup_flow.dart:985-996`). `startTvListener` has no idempotence or
readiness guard and constructs fresh services (`remote_control_state.dart:49,64`),
while `switchToReceiverMode` stops everything first (`:263`). Two starts can
race the socket bind, and `isTv == true` does not mean "listening".

This ships today and the redesign does not cause it — but the import step is
being rebuilt in Phase 4 anyway, so the fix lands there.

**A serialised start is not enough: it needs a lease, and every role change
must go through the same queue.** Backing out of import restores the previous
role — sender, or fully stopped when remote control is disabled — guarded by
`_switchedRoleForImport` (`initial_setup_flow.dart:969-1019`), and
`switchToReceiverMode`/`switchToSenderMode` are stop-then-start sequences
(`remote_control_state.dart:263`). A back-out that lands while a start is still
in flight can therefore restore first and bind second, leaving a phone or
desktop advertising itself as a receiver.

```dart
Future<ReceiverLease> ensureReceiverMode(String name);  // idempotent, resolves when BOUND
class ReceiverLease { Future<void> release(); }         // restores the prior role
```

- One `Future` queue in `RemoteControlState` covers **receiver start, sender
  restore and stop** — not just the starts.
- **Each caller gets its own handle.** A second `ensureReceiverMode` binds
  nothing new but returns a **distinct lease**, and the role is restored only
  when the **last** one is released. Handing both callers the same object would
  let the import step release the initializer's permanent TV lease on back-out
  — silently killing the listener that makes a TV discoverable at all.
- `release()` is a no-op if this lease did not change the role — which is
  exactly what `_switchedRoleForImport` encodes today
  (`initial_setup_flow.dart:992`, `:1005`), moved somewhere it can be tested.
- `AppInitializer._startTvListenerEarly` takes a lease it never releases (the
  TV's default role); the import step takes and releases its own.

Test: back out **while a start is pending** and assert the device ends in its
prior role. Round 1 recorded this finding without fixing it; that was wrong.

### 8b Phase 0a harness — what it takes to pump the current widget

Established by review against the code, so nobody rediscovers it:

| Concern | Reality |
|---|---|
| Pumping at all | Fine. The first frame builds the mode chooser; platform detection is only *scheduled* (`initial_setup_flow.dart:367`, `698`). |
| Prefs | Seed `SharedPreferences` — every relevant read/write goes straight to it (`storage_service.dart:1721`). |
| HTTP | Needs an **`HttpOverrides`-level** fake, not constructor injection: the widget builds its own `RemoteEngineManager` in a field initialiser (`:193`, `remote_engine_manager.dart:57`). Covers validation, engines and both tracker flows. |
| TV branch | `PlatformUtil.debugSetAndroidTvCached` is `@visibleForTesting` and exists (`platform_util.dart:18-28`); on a non-Android host it resolves false anyway. |
| Settling | **Never `pumpAndSettle` after entering import or an auth flow** — the import screen runs a repeating animation *and* a periodic timer (`:959`, `:1126`), and the tracker polls run their own. Bounded `pump(Duration)` only. |

**One production change belongs to 0a, and it is behaviour-neutral.** The
phone-import path cannot be characterised hermetically today: choosing it
constructs the process-wide `RemoteControlState` singleton and calls
`switchToReceiverMode` (`:985-996`), which builds real UDP services and binds
sockets (`remote_control_state.dart:64`, `udp_discovery_service.dart:75`,
`udp_command_service.dart:111`). The singleton has no test seam
(`remote_control_state.dart:15-19`) and `stop()` leaves `_isTv` set (`:139-149`),
so tests would be order-dependent even if the sockets behaved.

0a therefore adds **one `@visibleForTesting` reset** on `RemoteControlState` —
the same shape as `PlatformUtil.debugSetAndroidTvCached`, which exists for
exactly this reason. It nulls the services and clears `_isTv`, and **no shipped
code path calls it.**

> **It must be a test-only reset, not a change to `stop()`.** An earlier draft
> proposed having `stop()` clear `_isTv` and called that behaviour-neutral. It
> is not: `isTv` is public and shipped branches read it *after* a stop —
> `initial_setup_flow.dart:993` decides whether the import step switches roles
> at all, and `remote_role_picker_screen.dart:73` decides whether opening the
> sender needs a switch. Clearing it inside `stop()` would change both.
> `stop()` is untouched.

Without the reset, "characterise phone import before rewriting it in Phase 4"
is not a thing that can be done, and pretending otherwise would mean rewriting
an untested path.

---

## 9. Tests

Follow `test/theme/spotlight_spec_test.dart`, which greps the mock off disk so
retuning HTML without retuning Dart fails the build.

1. **`onboarding_bands_test`** — pump the key step at **960×540 logical** (TV)
   and 360×740. Assert (a) the field's bottom ≤ the keyboard band's top, (b)
   **the panel's own painted rect is inside the band**, and (c) no layout
   exception is recorded — a child overflowing its band is invisible to a
   bounds-only comparison. Run all three at default text scale **and at 1.3**,
   and with a notice bar showing. **This test must never be deleted.**
2. `onboarding_keyboard_slot_test` — with a slot present the panel renders in
   the band and **no `OverlayEntry` is inserted**; with no slot the overlay path
   is unchanged. Teardown, one case each: `_endEdit`, **the system-IME key**
   (`_switchToSystemIme` bypasses `_endEdit`, `:496`), and **removing the field
   while the slot stays mounted** — after each, the notifier is null, the panel
   is gone, and no disposed controller is retained. Plus: a detach for a stale
   controller does not blank a newer session.
3. `onboarding_focus_test` — per step: landing node matches the table; LEFT at
   col 0 focuses Back; RIGHT returns; no move escapes the grid. Plus the two
   contracts round 2 added: **Back driven through `handlePopRoute`** in every
   state of the §3.4 table (keyboard open, provider 2, provider 1, importing,
   mode) — not by activating a focused button, which is a different path — and
   the keyboard exit of §6a: **Back closes the panel**, focus lands on the field
   shell, and LEFT from the shell reaches the Back control. *(An earlier draft
   asked for "UP out of every keyboard row"; UP cannot leave the keyboard and
   the plan no longer pretends otherwise.)*
4. `onboarding_flow_test` — mode → services → engines → trackers(skip) → done.
   **Expect `true` when the default engine import succeeds**: engines are
   auto-selected (`4301`) and a successful import sets `_hasConfigured` (`4389`),
   which the pop returns (`3929`). Only a run that chooses **Turn all off** and
   connects nothing may expect `false`. Also covers system Back and Skip both
   marking setup complete.
5. `onboarding_engines_test` — stub manifests of 3 and 11 both render, all
   pre-selected, and **no literal `8`** appears in the tree. Descriptions: an
   entry **with** `description:` shows it, an entry **without** one renders name-
   only, and a manifest that omits the field entirely (today's live file) renders
   the whole grid name-only rather than throwing.
6. `onboarding_key_test` — the canonicalisation path (§5.3): type a raw key,
   type a pre-grouped key, and **type and paste `nonav:<key>`**, all validating
   identically. For the `nonav:` cases assert the **side effect** —
   `setRealDebridHiddenFromNav(true)` was called — not merely that validation
   succeeded. The Paste chip goes through `insertText` (assert the formatter ran
   and `onChanged` fired; a test that sets `controller.text` would pass against
   a broken chip). Unknown-length providers show `n characters`.
7. `onboarding_route_test` — normal pop returns to the initializer; a remote
   `config/complete` mid-flow removes the route and the caller's `mounted` guard
   holds.
8. Existing suite green. The **8 pre-existing failures** recorded in
   `project_discover_sort_memory` are not ours.

---

## 10. Open questions

- **O1 — system bars.** Confirm on device that a themed subtree under the
  bootstrap freeze does not fight `system_bars.dart` (§3.2). The only one left.

*(Resolved: **voice stays** — the mic key is kept on the key step, 2026-08-12;
§5.2's slot gives it for free because the field is retained, and it is the one
input where a remote is not the bottleneck. **Engine copy lives in
`metadata.yaml`**, 2026-08-12, §6. The Spotlight-scope question — both halves,
§3.2. The skip-semantics question — leave ≡ skip, §6.)*

---

## 11. Deliberately not in scope

- The splash / launch ident / migration path — one line changes, no behaviour.
- The remote-control protocol, the sender UI, and `RemoteCommandRouter`'s
  handlers, including `_handleConfigComplete`'s restart. Receive side is used
  as-is, from the import step only.
- **Per-provider phone send** — §5.4, with the two pieces of router work it
  would need.
- Provider set. No new debrid services; every existing validation path is kept.
- Backup/restore, WebDAV, IPTV, addons — none are first-run decisions.

---

## 12. Review log — round 1 (codex, 11 P1 + 3 P2)

| # | Finding | Resolution |
|---|---|---|
| 1 | Per-provider phone send ends onboarding: `complete` is sent after any batch and restarts the app | **Accepted.** Method cut; the chip now routes to the import step (§5.4). |
| 2 | `addHandler` fires before validation, which is unawaited — a listener can't tell good from bad | **Accepted.** Dissolved by #1; recorded as a precondition for the deferred variant. |
| 3 | `_startReceiveMode` can't be reused "exactly"; receiver start races `_startTvListenerEarly` | **Accepted.** Only the import step starts receive mode, exactly as today. The idempotent receiver-session API is listed as deferred work, not smuggled in. |
| 4 | Keyboard band 226 < 240 minimum | **Accepted.** Band is 268 (§5.1) with the arithmetic shown; `maxWidth` demoted to optional polish. |
| 5 | A bare host drops hardware keyboards, voice, IME and paste | **Accepted, and it changed the design**: `TvKeyboardSlot` moves the panel and keeps the field (§5.2). |
| 6 | `FrozenLegacyPageRoute` injects the boundary; the post-publish concern doesn't occur | **Accepted.** `PageRouteBuilder` on the root navigator; the bogus concern deleted (§3.1). |
| 7 | `AppThemeScope` doesn't change `Theme.of` | **Accepted.** `Theme` + `AppThemeScope`, both memoised (§3.2). |
| 8 | `ParallaxShape.card` doesn't exist; `FocusExpressionBox` isn't a no-op | **Accepted.** Real shapes mapped; `FocusExpressionBox` explicitly not used (§4). |
| 9 | Phase 1 enabling a half-built flow | **Accepted.** Flag off until Phase 4 (§1.3, §8). |
| 10 | Phase 0 is a lifecycle refactor, not a file move, with no tests under it | **Accepted.** Split into 0a (characterisation tests first) and 0b (controllers, not `part of`) (§8). |
| 11 | The `false` return test contradicts the shipped meaning | **Accepted.** Test corrected with its reasoning (§9.4). |
| 12 | 40 chars is Real-Debrid only | **Accepted.** `keyLength` nullable per provider (§5.3). |
| 13 | The catalogue supplies no descriptions | **Accepted.** *(Round-1 answer was a local map; superseded 2026-08-12 — the copy goes upstream into `metadata.yaml` and the parser reads it, keeping the name-only fallback. §6.)* |
| 14 | "Leave" and "skip" are indistinguishable through the shipped API | **Accepted as a decision, not a defect.** They are the same thing on purpose (§6), and tested. |

## 13. Review log — round 2 (codex, 8 P1 + 1 P2)

| # | Finding | Resolution |
|---|---|---|
| 1 | System Back has no state-dependent contract, and a stage `PopScope` collides with the field's — every `PopEntry` is notified on a blocked pop | **Accepted.** New §3.4: one owner, a state table, and the single guard (stage handler returns early while a keyboard session is attached). Tested through `handlePopRoute`, not button activation. |
| 2 | Slot teardown misses `_switchToSystemIme`, and clearing the notifier from `dispose` notifies during teardown / can't look up an inherited widget | **Accepted, design changed.** `TvKeyboardSession` with identity-checked attach/detach, all three exits enumerated, cached slot ref, deferred notify (§5.2). |
| 3 | 268 is still short — the notice sits above all five rows and adds ~35 | **Accepted, and the number is gone.** The band **measures** the panel (`Expanded` field + intrinsic keyboard, floor 275); the invariant is now structural, and the test checks the panel's own rect and layout exceptions at 1.0 and 1.3 text scale (§5.1, §9.1). |
| 4 | Grouping corrupts `nonav:`; the Paste chip can't reach the private insert path | **Accepted.** One canonicalisation path (`splitKey`/`group`/`canonical`) grouping the payload only, plus a public `TvTextFieldState.insertText` shared by the chip and the keyboard key (§5.3, §9.6). |
| 5 | The receiver-start race was recorded, not fixed | **Accepted — round 1 was wrong to log it as handled.** `ensureReceiverMode` lands in Phase 4 with both callers routed through it (§8a). |
| 6 | Phase 4 can't show truthful per-item progress: listeners fire pre-validation, no total is transmitted | **Accepted.** §6b narrows the panel to connection + received count + indeterminate "applying…". **The mock is overruled here** — its determinate bar is a fiction. |
| 7 | Phase 0a characterises a done screen and a Back that don't exist | **Accepted.** 0a now pins `trackers → pop` and the two *absences*; V2 assertions moved to Phase 4 (§8). |
| 8 | Width-only breakpoints send the 960×540 television to the tablet layout | **Accepted — the sharpest finding of the round.** Television is checked first and wins at any size, mirroring `resolveDetailSize`; TV tests run at 960×540 (§7). |
| 9 | "No wrapping" contradicts the keyboard's deliberate horizontal wrap | **Accepted.** Declared exception in §1.4. *(The UP-exit half of this answer was wrong and round 3 caught it — see below.)* |

## 14. Review log — round 3 (codex, 4 P1)

| # | Finding | Resolution |
|---|---|---|
| 1 | Back still double-acts: `_armPopGuard()` runs **before** `_endEdit()`, so the panel is already detached when the nav-channel pop arrives and the stage's guard is open | **Accepted.** The signal moved off "is a panel attached" onto `session.ownsBack`, which the field asserts from `_armPopGuard` and which outlives the detach by the same 300 ms window. The test now drives the **sequence** (Back-down, then `handlePopRoute` inside the window), because a state-only test passes against the bug (§3.4, §9.3). |
| 2 | UP cannot escape the keyboard: `_KbNavAction` consumes every arrow and `nav` clamps at row 0 | **Accepted; §6a was wrong and is rewritten.** No top-edge exit is added — that would be the routing change §5.2 promises not to make. The exit is **Back**, the shipped idiom, plus the caret-position caveat on `_EdgeLeftAction` that §9.3 now tests both ways. |
| 3 | `canonical()` drops `hideNavOnSave`; every planned test would still pass | **Accepted.** `parseKey` returns `(key, hideFromNav)`, and the test asserts the **side effect** — the provider is actually hidden — not just that validation succeeded (§5.3, §9.6). |
| 4 | `ensureReceiverMode` serialises starts but not the opposing restore; a back-out can race a pending start | **Accepted.** It returns a **lease**; one queue covers start, sender-restore and stop; `release()` no-ops when the role was not changed. Tested by backing out mid-start (§8a). |

## 15. Review log — round 4 (codex, 4 P1)

Two of these were stale text in this document rather than design faults — which
is its own lesson about revising a 700-line plan in place.

| # | Finding | Resolution |
|---|---|---|
| 1 | Phase 0a can't characterise phone import: `RemoteControlState` is a singleton with no test seam that binds real UDP sockets, and `stop()` never clears `_isTv` | **Accepted, and it adds one test-only seam to 0a** — a `@visibleForTesting` reset modelled on `PlatformUtil.debugSetAndroidTvCached`. Without it Phase 4 would rewrite an uncharacterised path (§8b). *(The first version of this answer also changed `stop()`; round 5 caught that — see below.)* |
| 2 | §9.3 still demanded "UP out of every keyboard row" after §6a had established UP cannot leave | **Accepted — stale text.** The test now asks for the real exit (Back → shell → LEFT). |
| 3 | The `_EdgeLeftAction` caret caveat governs passthrough mode, not the TV shell — `_handleShellKey` calls `onLeftArrow` unconditionally | **Accepted; §6a's claim was false** and is corrected with the right line references. The practical effect is better than described: LEFT works at any caret position. |
| 4 | One shared lease lets the import step release the initializer's permanent TV lease | **Accepted.** Distinct per-caller handles, restore on last release (§8a). |

Confirmed sound by this round: `session.ownsBack` tied to `_armPopGuard` and its
300 ms window, and `parseKey` preserving the `nonav:` side effect.

## 16. Review log — round 5 (codex, 1 P1)

| # | Finding | Resolution |
|---|---|---|
| 1 | §8b called "`stop()` clears `_isTv`" behaviour-neutral. It isn't: `isTv` is public and shipped branches read it after a stop (`initial_setup_flow.dart:993`, `remote_role_picker_screen.dart:73`) | **Accepted.** `stop()` is untouched; the seam is a **test-only reset** that no shipped path calls (§8b). |

Rounds 1–5 verified §§3.1, 3.2, 3.4, 5.1–5.4, 6a, 7, 8a and 8b against the
source. **Phase 0a is ready to start** — characterisation tests for the current
widget, plus that one `@visibleForTesting` reset.
