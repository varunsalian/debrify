# Portable launch animations, version 1

This is an app-independent **playback profile for dotLottie**, not a new archive
format. An exporter can generate one static `.lottie` file containing custom
outlined text and fixed colors. A compatible application needs no website,
account, network request or Debrify-specific asset to play it.

Debrify's implementation pins Flutter `lottie` 3.5.1. “Compatible” means the
selected animation satisfies the limits below and its preview renders correctly;
it does not mean every feature of dotLottie or After Effects is supported.

## Export and packaging

Use a ZIP with `manifest.json` at its root, with `version` equal to `1.0` or
`2.0` and a nonempty `animations` array. Each entry has an `id` and may have a
`name` and opaque `background` such as `#081020`. IDs start with an ASCII letter,
digit, `_` or `-`; subsequent characters may also include `.` (128 characters
maximum). Use unique, case-distinct paths without absolute paths or traversal.

- v1 animation JSON: `animations/<id>.json`.
- v2 animation JSON: `a/<id>.json`.
- Pack image assets into the ZIP; their JSON `u` + `p` references may be
  archive-root or animation-relative. PNG and JPEG are recommended. Embedded
  PNG/JPEG data URIs also work. Assets must decode to a single image frame.
- For multiple animations, v2 `initial.animation` or v1 `activeAnimationId`
  chooses the default when present; otherwise the first manifest entry does.
  The importing user chooses one composition, except for an automatic orientation
  pair: exactly two IDs named `<name>-portrait` and `<name>-landscape`, with
  the same `<name>`, respectively tall/wide canvases, and identical `fr`, `ip`,
  and `op`. These import without a chooser and switch with the playback area
  shape (square uses landscape), including rotation and preview resizing.
  Both variants are validated and loaded; keep both lightweight. Existing
  imports of matching pairs also switch automatically. Other packages retain
  explicit composition selection. This naming convention is optional and
  does not change the dotLottie manifest schema.
- ZIP compression must be stored or deflate. Encrypted archives, links,
  ambiguous paths and missing assets are rejected.

Minimal v2 manifest:

```json
{"version":"2.0","initial":{"animation":"hello"},"animations":[{"id":"hello","name":"Hello","background":"#081020"}]}
```

## Artwork and playback

Convert every letter to vector paths before export. Choose final colors during
export; the importing app does not substitute text, apply themes or recolor
artwork. Expand repeaters and flatten merged paths into ordinary shapes. Keep important artwork centered
with generous margins and check both portrait and landscape previews.

Playback scales proportionally to fit the viewport and centers the result over
an opaque background. It never stretches or crops to fill. Letterboxing is
expected when the artwork and screen have different aspect ratios. Layout
changes do not restart playback. Make the final frame attractive and complete:
the player runs once at the authored rate, ignores looping and holds the final
rendered frame while the application finishes loading.

In Debrify, Home starts loading after the reveal. A five-second animation is
therefore not a five-second total startup promise: Home can take its existing
10-second readiness timeout plus the exit transition. Local animation loading
has a one-second deadline; a load failure or timeout uses the built-in animation
for that launch. Late results cannot replace it. A recoverable drawing error
settles the built-in fallback without replaying it.

## Compatibility

| Feature | Contract and evidence |
| --- | --- |
| 2D shapes, fills, transforms, opacity, outlined text | Supported within budgets; original HELLO fixtures exercise these. |
| Packaged images | Supported within decoded-pixel limits; `hello-image` exercises an image. |
| Linear gradients, additive masks | Limited to renderer behavior and complexity budgets; `hello-features` exercises these. |
| Radial gradients, alpha and inverted alpha mattes | Limited to renderer behavior and budgets; `hello-radial` and `hello-mattes` exercise these. |
| Luma mattes, merged paths | Unsupported; flatten these into ordinary paths before export. |
| Precompositions | Supported when acyclic, at most 16 levels and 200 expanded layer instances. |
| Live text/fonts, 3D, audio layers, layer effects | Unsupported; export 2D paths/images instead. |
| Expressions, dynamic slots, repeaters | Unsupported; export fixed values and expanded shapes. |
| State machines and package themes | Not executed/applied; package-level declarations produce a warning. An independent compatible composition may still be imported. |
| External files, scripts, network resources | Never fetched or executed. Required image dependencies must be packaged. |

Known unsupported features are rejected. Renderer warnings appear with preview;
an accepted parse alone is not visual verification. Preview the complete animation
before choosing Use. Some unsupported exporter constructs may be ignored by the
renderer, so compare the preview with the intended artwork.

## Enforced limits

| Resource | Maximum |
| --- | --- |
| Compressed package | 10 MiB |
| Total ZIP expansion, enforced during decompression | 40 MiB |
| Archive entries | 256 |
| Selected duration | 5 seconds |
| Authored frame rate | 60 fps |
| Composition width or height | 8192 units |
| Single decoded image | 8,388,608 pixels |
| Total decoded images | 16,777,216 pixels |
| JSON nesting / decoded nodes | 64 / 200,000 |
| Declared and expanded layers | 200 |
| Referenced composition nesting | 16 |
| Declared and expanded mask/matte instances | 16 |
| Declared and expanded path vertices, including keyframes | 10,000 |

These are rejection ceilings, not recommended production targets or frame-rate
guarantees. Start with small vector artwork at 30 fps. Physical lower-powered TV
measurements are still required to approve these ceilings for release; avoid
shipping content close to them before those measurements.

## Original examples

`samples/hello-landscape.lottie` is v2, `hello-portrait.lottie` is v1, and
`hello-multiple.lottie` contains both compositions. `hello-image.lottie` adds an
original packaged PNG. `hello-features.lottie` demonstrates a linear gradient and mask.
`hello-radial.lottie` uses a radial gradient; `hello-mattes.lottie` keeps the
left half of the word on its top row and the right half on its bottom row, using
alpha and inverted alpha mattes.
All artwork is generated locally without external fonts or assets. Regenerate
with `python3 dev/launch_animations/generate_samples.py`; `sample_data.dart` is
used only by the development verification entry point.

## Debrify import and TV delivery

Open Launch Animation settings, import a file, choose a composition if prompted,
watch the preview, choose a background and select Use animation. Import alone
never changes the active animation. Built-in choices remain available.

The installed library is shared on the device; selection belongs to the active
profile. Deleting an animation affects every profile that uses it. Missing files
(including tvOS cache eviction) fall back safely. Backups and cross-device profile
sync omit the device-local selection; restoring a profile clears its override.

From an imported animation's detail screen, Send to TV uses Debrify's existing
paired transfer connection. Both devices must support protocol 8. The selected
composition and background travel with the original package. The receiving user
must preview and choose Use in settings; transfer does not activate it. tvOS uses
this path because it has no file picker.

The animation files remain standard portable content; the paired delivery
protocol is Debrify-specific and is not required by other adopting applications.
