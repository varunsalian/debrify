import 'dart:async';

/// Bounds the whole initial board load, including local credential reads.
/// Expiration must retire the caller's generation before the timeout reaches
/// its error UI: Future.timeout does not cancel the underlying work.
Future<void> runHomeLoadWithDeadline({
  required Future<void> Function() load,
  required void Function() retire,
  Duration timeout = const Duration(seconds: 25),
}) => Future<void>.sync(load).timeout(
  timeout,
  onTimeout: () {
    retire();
    throw TimeoutException('Home took too long to load. Please try again.');
  },
);

/// An immutable snapshot published only when a board load or page is accepted.
/// Every overlapping refresh recovers this same committed state, rather than
/// taking a new snapshot of another refresh's tentative references.
class HomeBoardSnapshot<T, A> {
  HomeBoardSnapshot(List<T> references, this.cursor, Map<String, A> addons)
    : references = List<T>.unmodifiable(references),
      addons = Map<String, A>.unmodifiable(addons);

  final List<T> references;
  final int cursor;
  final Map<String, A> addons;

  int restore(List<T> target, Map<String, A> targetAddons) {
    target
      ..clear()
      ..addAll(references);
    targetAddons
      ..clear()
      ..addAll(addons);
    return cursor;
  }
}
