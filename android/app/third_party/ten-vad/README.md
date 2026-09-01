# ten-vad (prebuilt)

Neural voice-activity detector used by the Android TV player's subtitle
auto-sync (`SpeechFeatureTap` → `TenVad`). Prebuilt shared libraries only;
the app links a tiny JNI shim against them (`src/main/cpp`).

- Upstream: https://github.com/TEN-framework/ten-vad
- Commit: 22a3bcd4509d0faaa8eef4881e8af5f39c178950 (2026-02-02)
- Files: `src/main/cpp/prebuilt/{arm64-v8a,armeabi-v7a}/libten_vad.so`,
  `src/main/cpp/include/ten_vad.h`
- Licence: Apache-2.0 with additional conditions (see LICENSE) plus BSD code
  from LPCNet (see NOTICES). Debrify is an end-user application, which the
  licence's deployment terms permit. Attribution: "Powered by ten-vad".
- ABIs without a prebuilt (x86_64) build no shim; the app detects the
  missing library at runtime and falls back to energy features.
