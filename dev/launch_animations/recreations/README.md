# Debrify launch animation recreations

Three self-contained dotLottie v2 packages, recreated from the existing native launch styles.

| File | Duration | Artwork |
| --- | --- | --- |
| [trace.lottie](trace.lottie) | 2.4 seconds | Traveling light, sequential letter flashes, retracting underline |
| [swiss.lottie](swiss.lottie) | 1.8 seconds | Vermilion rule and play block, bold rising wordmark |
| [monogram.lottie](monogram.lottie) | 2.2 seconds | Drawn ring, purple play mark, spaced caption |

Import a `.lottie` file in Debrify's launch animation settings. Preview it, then apply it. Each package contains portrait and landscape compositions. Debrify automatically chooses from the playback area shape and switches on rotation; there is no orientation chooser. Both versions fit without cropping. Existing imports also gain automatic selection when the app is updated.

All three use vector shapes with outlined lettering, and need no fonts, images, network access, or Debrify-specific runtime code. They are visual recreations rather than pixel-exact exports: lettering uses bundled Inter, Trace uses a flat background and layered vector lights, and Swiss's block rises into its clipping plane.

Final-frame previews: [Trace landscape](previews/trace-landscape.png), [Trace portrait](previews/trace-portrait.png), [Swiss landscape](previews/swiss-landscape.png), [Swiss portrait](previews/swiss-portrait.png), [Monogram landscape](previews/monogram-landscape.png), [Monogram portrait](previews/monogram-portrait.png).

## Regenerate or customize

From the repository root:

```sh
python3 -m venv /tmp/debrify-lottie-tools
/tmp/debrify-lottie-tools/bin/pip install -r dev/launch_animations/requirements-recreations.txt
/tmp/debrify-lottie-tools/bin/python dev/launch_animations/generate_recreations.py
```

Generate a different main wordmark without replacing these fixtures:

```sh
/tmp/debrify-lottie-tools/bin/python dev/launch_animations/generate_recreations.py --text 'CINEMA' --output /tmp/cinema-animations
```

The main wordmark accepts 1–24 characters supported by the bundled font. Swiss's small secondary captions remain unchanged. Colors and motion are authored in the generator; changing outlined lettering requires regeneration.

## Validation

Six automated tests import, install, load and paint both variants of each package using the application's importer and player. They check motion, visible final artwork, and absence of parser/render warnings. Scoped Dart analysis passes.

Android TV emulator profile playback covers both variants at 9:16, 16:9 and 21:9 (18 runs). See `verification.json` for measurements and package hashes. Emulator measurements are not physical-device performance guarantees. Physical-device QA is deferred as requested.

These packages and their embedded Dart fixture data are development artifacts; they are not added to production application assets.
