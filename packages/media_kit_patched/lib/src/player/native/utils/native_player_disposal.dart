/// Completes the two native operations whose order is critical during player
/// teardown.
///
/// The mpv wakeup callback must stay alive until `mpv_terminate_destroy` has
/// returned: clearing mpv's callback prevents new invocations, but a callback
/// already queued for Dart may still be in flight. The callback is also closed
/// when termination throws so a failed teardown does not leak its trampoline.
Future<void> completeNativePlayerDisposal({
  required Future<void> Function() terminate,
  required void Function() closeWakeupCallback,
}) async {
  try {
    await terminate();
  } finally {
    closeWakeupCallback();
  }
}
