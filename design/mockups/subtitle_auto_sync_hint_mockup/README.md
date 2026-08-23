# Subtitle auto-sync hint mockup

Interactive player mock exploring how to show the full default-on subtitle auto-sync lifecycle without interrupting playback.

Open `index.html` in a browser. It includes three animated placements, macOS/Android TV sizing, success/failure endings, and a replay control. The usual ~90-second success lifecycle is compressed to 12 seconds; failure runs 16 seconds to demonstrate the 180-second fallback.

The recommended pattern is **A · Control anchor**: keep a compact status pill above the subtitle-controls zone throughout capture. Update it at the 20, 45, and 90-second attempts, briefly show the final result, then fade it away.

Suggested production policy:

- Show the activity hint immediately after an addon subtitle becomes active.
- Keep it visible through the complete attempt ladder.
- Use real elapsed time rather than a fake percentage; analysis may finish early or extend to 180 seconds.
- Briefly change the label to “Checking timing” at each attempt, then return to listening/refining.
- Never cover subtitle text or steal remote focus.
- Announce success only after an offset is applied.
- Show the success or failure result for about two seconds, then disappear.
- Respect reduced-motion settings by replacing rotation/morphing with a simple cross-fade.
