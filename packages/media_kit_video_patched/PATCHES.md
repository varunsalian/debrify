# Debrify native render-context shutdown

Base: pub.dev `media_kit_video` 2.0.1. Dart, Android and Linux
implementations are unchanged. Upstream LICENSE is retained.

The Apple Dispose method previously removed a VideoOutput from a dictionary and
immediately replied to Dart. Its worker jobs and Flutter texture registry could
still retain the output/texture. Dart then called mpv_terminate_destroy before
mpv_render_context_free, triggering libmpv's fatal mp_clients_destroy abort.

- VideoOutput explicitly disposes the render context on its worker, after prior
  initialization/render work. It then unregisters the texture on the main queue.
- VideoOutputManager coalesces duplicate disposals and responds only after both
  steps complete. Dart's existing awaited release hook now provides a real
  teardown barrier before native player destruction.
- Hardware and software textures free the render context explicitly and
  idempotently, independently of Swift ARC / Flutter texture retention.
- Render jobs check disposal before reading the mpv handle. Canceled workers
  reject/drop pending jobs, avoiding late handle access and retained closures.

The shared Apple files also compile into upstream's iOS plugin. Debrify's
separate media_kit_video_tvos package is not changed by this override.

Native validation: see tool/native_video_disposal_probe.dart. Run a macOS release
build against a localhost-served test video; it cycles hardware/software players,
waits for a rendered frame, unmounts each texture and awaits player disposal.

The published package contains physical copies of common Darwin Swift sources
under both ios/Classes/plugin/common and macos/Classes/plugin/common. Keep these
copies identical to common/darwin/Classes/plugin when updating the patch.

Validation on 2026-09-07:
- A release-mode probe with the old Dispose acknowledgement reproduced the same
  mp_clients_destroy.cold.2 abort as the user crash.
- Patched macOS release probe: 30 hardware + 10 software rendered player
  create/unmount/dispose cycles, all completed without a native crash.
- Trailer/focus/lease widget regressions: 11 passed. Native callback-lifetime
  regressions: 2 passed.
- iOS shares the changed Swift source but has not been runtime-tested here.

## Windows

Windows previously acknowledged Dispose as soon as it launched a detached
cleanup thread. The output destructor also queued render-context destruction
without waiting for it. The Dart player's five-second grace period therefore
did not guarantee that the render context was gone before player termination.

- Dispose now completes only after the output destructor finishes. Duplicate
  calls wait behind the same manager lock. The channel reply is posted back to
  the platform thread, which remains free during cleanup.
- The destructor disables render callbacks, drains pending work, waits for
  texture unregistration, then frees the render context on the render worker
  before destroying its ANGLE context. It waits for that final job too.
- Outputs without a registered texture also finish teardown. Previously they
  waited on a promise that nobody fulfilled.
- The cross-thread destruction flag is atomic; queued render/resize work skips
  disposed outputs.
- Worker replies use a shared dispatcher rather than calling back through a raw
  plugin pointer. Plugin teardown closes the dispatcher before detaching the
  window procedure, discards pending tasks, and rejects late posts. Resize
  notifications use the same dispatcher, so their queued plugin access is also
  canceled at shutdown.
- Create, SetSize and Dispose run on one manager-owned FIFO worker instead of
  detached threads. The manager destructor queues output cleanup after accepted
  work and drains/joins the worker before releasing manager state. The operation
  worker is separate from the render worker, since output teardown waits for
  render jobs. This also preserves Create/SetSize/Dispose submission order.

Run `python3 packages/media_kit_video_patched/test/windows_disposal_test.py` from
the repository root. It compiles the actual destructor and manager disposal
bodies with controlled native fakes and the production render queue. It checks
delayed texture unregistration, delayed render-context cleanup, duplicate and
missing handles, hardware/software ordering, and uninitialized outputs.
It also runs the production dispatcher under AddressSanitizer, covering queued
and late callbacks after plugin destruction, teardown during task execution,
and concurrent Post/Close calls.
The manager tests run under AddressSanitizer too: shutdown must wait for a paused
worker to complete disposal, and must finish texture/render-context cleanup for
an active output before returning.
These checks run on macOS; a Windows build and real playback stress test remain
required to validate Flutter, ANGLE and libmpv integration on Windows.
