# profiles_mockup

A redesign of the two profile surfaces: the **gate** (the first screen, currently
`profile_picker_screen.dart`) and a new top-level **Settings → Profiles** page.

Open `index.html` directly in a browser.

- Switch surface with **The gate** / **Settings → Profiles** / **Edit profile**.
- On the gate, try all three concepts: **A · Portrait Wall**, **B · Spotlight Stage**,
  **C · Halo Row**.
- `←` `→` move focus (`↑` `↓` in Spotlight Stage and in phone view); click also works.
- Toggle **TV / Desktop** and **Phone** above the frame.

Palette is the shipped Spotlight one (`#0D1420` ground, `#151D2A` raised,
`#E23D4C` accent) with onboarding's mono eyebrow and inverse-white focus, so this
sits in the same room as the Spotlight home and the settings redesign.

Avatars here are generated with CSS gradients and keyframes rather than real
files — that keeps the mock self-contained while still demonstrating the actual
behaviour, including still-versus-animated.

## Why

| Today | This mock |
|---|---|
| Material `Card` grid, gradient circle, one of six fixed icons | Portrait tiles carrying images, GIFs, art packs or a monogram |
| No relationship to the shipped Spotlight look | Spotlight ground, inverse focus, avatar-derived ambient wash |
| Every tile equally lit; focus reads as a thin ripple | Unfocused tiles desaturate and recede; focus lifts, rings, animates |
| **No Profiles page in Settings at all** | Top-level category holding the roster plus two device-wide rows |
| Avatar choice is six `ChoiceChip`s labelled with raw keys (`movie`, `rocket`) | A picker inside Edit profile: built-in art, image or GIF, send-from-phone |
| Lock state is a small grey padlock under the name | Padlock badge on the tile, PIN chip on the focused profile |

## The three gate concepts

**A · Portrait Wall** — 3:4 portrait tiles in a centred row. The most room for
imagery and the most cinematic; closest in spirit to the Spotlight home.

**B · Spotlight Stage** — one large focused avatar with name, role and last-watched
beside it, and a compact rail of the others. Reuses the shipped Spotlight
stage-plus-rail grammar, and shows a GIF at the largest size of the three.

**C · Halo Row** — circular avatars in a single row. The familiar "who's watching"
idiom, kept premium with an animated ring and focus-only playback. The safest,
and the cheapest to build.

## Behaviours worth keeping whichever concept wins

- **Only the focused avatar animates.** Everything else holds a still frame. A wall
  of looping GIFs is noise on a phone and a decoder storm on a weak TV box; one
  moving element is also how the eye finds focus from across a room, so the
  animation doubles as the focus indicator. There is a Settings toggle for it.
- **The room takes the focused avatar's colour** — a blurred bloom behind the row
  plus a matching halo, repainting as focus moves.
- **Three ways to get a picture onto a TV**: built-in art, a file pick, or
  send-from-phone over the pairing channel that already exists. The last matters
  most — nobody wants to browse a filesystem with a D-pad.
- **Settings → Profiles is top-level**, next to Appearance and Connections, rather
  than hidden behind a button on the picker that a sole-profile user rarely sees.

## Where the settings went

The hub is deliberately short: the roster, then two device-wide rows (plus one
Apple-TV-only toggle). Everything else was either about **one person** — so it
belongs in that person's profile — or already had a home elsewhere.

| Row | Now lives |
|---|---|
| Avatar library, add-from-phone, animate-on-gate | Edit profile → Avatar |
| Require a PIN, change PIN | Edit profile → Lock |
| Diagnostics, reset this profile | Edit profile → Data |
| Back up this profile | Existing Backup section — it was a second front door |
| Gate style (Wall / Stage / Halo) | Appearance, beside the other `*_style` pickers |
| "Always ask" + "skip when sole" + "remember last" | One row: **Ask who's watching** |

That last one is the biggest saving: three overlapping toggles were really one
question with three answers.

## Two different permission systems — don't confuse them

**The `ProfileFeature` policy editor is OFF.**
`EditProfileScreen._showFeaturePolicyControls` is `false` in the shipped app: the
create/edit flows save the selected role's *complete* allowed feature set, and the
editor is parked for its own redesign. So this mock makes **role** the feature-level
control and says out loud what each role grants, instead of showing 19 switches
that don't exist. If that editor is revived, Edit profile is where it lands.

**Per-connection grants are very much ON**, and they are the heart of Edit profile —
this is the part the first draft of this mock missed entirely. The screen decides
what the profile may actually reach:

- **Torrent engines** — which installed engine definitions get *copied* into this
  profile. Each profile then keeps an independent copy and its own settings.
- **Shared connections** — every `ConnectionResource`: debrid and cloud accounts,
  trackers, **Stremio addons**, indexer managers, IPTV playlists, WebDAV. Each one
  is granted or not, and a *borrowed* resource (owned by another profile) expands
  into its `ResourcePermission` chips — `use` (always on), `download`,
  `writeRemote`, `manage`, `revealSecret`, `share`. Owned resources show an
  ownership badge and can be transferred.

The mock groups these by kind with an *n of m* count and All/None per group, so a
long roster stays scannable with a D-pad instead of becoming one flat checkbox
list.

## Open questions for the build

- **Where do avatar files live?** They are per-profile user data, so they need to
  land inside the profile's data generation and travel in the portable package —
  which makes them the first *binary* payload that backup/restore has to carry.
  Worth deciding before any of this is built.
- **GIF decode on weak boxes.** Flutter animates GIFs on the UI isolate. Focus-only
  playback keeps it to one at a time, but a large GIF may still want a frame cap
  or a downscale on ingest.
- **Kid profiles and photos.** Whether a Kid may set their own avatar, and whether
  Admin approval is required, is a policy question rather than a visual one.

This is a design artifact only; it changes no Flutter production code.
