/// Concurrency helpers.
library;

/// Runs [task] over [items] with at most [concurrency] tasks in flight at once,
/// returning the results in the SAME order as [items] (not completion order).
///
/// Unlike a bare `Future.wait(items.map(task))`, this never has more than
/// [concurrency] tasks running simultaneously — bounding the number of open
/// sockets, in-flight response buffers, and peak memory. That matters on weak
/// hardware (e.g. TVs) when [items] can be large: a user with hundreds of
/// searchable addon catalogs would otherwise fan out hundreds of concurrent
/// HTTP requests in one go and risk exhausting file descriptors or memory.
///
/// [task] is expected to handle its own errors (returning a sentinel/empty
/// value). If a task does throw, the error propagates out of this function
/// once all workers finish — like `Future.wait`'s default behaviour, the
/// throwing worker stops but the other workers still drain the remaining
/// items, so side effects for later items may still occur.
Future<List<T>> mapWithConcurrency<E, T>(
  Iterable<E> items,
  Future<T> Function(E item) task, {
  int concurrency = 10,
}) async {
  final list = items is List<E> ? items : items.toList();
  if (list.isEmpty) return <T>[];

  // Results indexed by original position so output order is deterministic
  // regardless of which task finishes first.
  final results = List<T?>.filled(list.length, null);
  var nextIndex = 0;

  // Each worker pulls the next unclaimed index until the list is exhausted.
  // Reading-then-incrementing nextIndex is atomic here because Dart runs this
  // isolate's code on a single thread and there is no await between the two.
  Future<void> worker() async {
    while (true) {
      final i = nextIndex;
      if (i >= list.length) break;
      nextIndex++;
      results[i] = await task(list[i]);
    }
  }

  // Clamp so a zero/negative concurrency (e.g. computed from a core count)
  // can't silently produce zero workers and an all-null result list.
  final safeConcurrency = concurrency < 1 ? 1 : concurrency;
  final workerCount =
      safeConcurrency < list.length ? safeConcurrency : list.length;
  await Future.wait(List.generate(workerCount, (_) => worker()));

  return results.cast<T>();
}
