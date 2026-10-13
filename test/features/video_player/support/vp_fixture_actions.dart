import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Records lifetime without attaching an error handler to production work.
/// The caller still owns the original Future and its error zone.
class VpFixtureActivity {
  VpFixtureActivity(this.label, {required this.held});
  final String label;
  final bool held;
  final done = Completer<void>();
  bool get isCompleted => done.isCompleted;
  void complete() {
    if (!done.isCompleted) done.complete();
  }
}

class VpFixtureTask<T> {
  VpFixtureTask(this.activity);
  final VpFixtureActivity activity;
  late final Future<T> future;
  bool get isCompleted => activity.isCompleted;
}

/// Entry and completion are separate: a held action cannot finish until its
/// test releases the barrier, often after asserting the intermediate effects.
class VpFixtureActions {
  VpFixtureActions() {
    current = this;
  }
  final activities = <VpFixtureActivity>[];
  static VpFixtureActions? current;
  static final _all = <VpFixtureActivity>[];
  static String? auditCase;

  static void Function() heldCallback(String label, void Function() callback) {
    final activity = current?.begin('barrier:$label', held: true);
    return () {
      try {
        callback();
      } finally {
        activity?.complete();
      }
    };
  }

  VpFixtureActivity begin(String label, {bool held = false}) {
    final activity = VpFixtureActivity(label, held: held);
    activities.add(activity);
    _all.add(activity);
    return activity;
  }

  VpFixtureTask<T> start<T>(
    String label,
    Future<T> Function() body, {
    bool held = false,
  }) {
    final task = VpFixtureTask<T>(begin(label, held: held));
    task.future = () async {
      try {
        return await body();
      } finally {
        task.activity.complete();
      }
    }();
    return task;
  }

  Future<VpFixtureTask<T>> entered<T>(
    WidgetTester tester,
    String label,
    Future<T> Function() body,
    bool Function() boundary,
  ) async {
    final task = start(label, body, held: true);
    await until(
      tester,
      boundary,
      reason: '$label must enter its held boundary',
    );
    expect(task.isCompleted, isFalse, reason: '$label must remain pending');
    return task;
  }

  Future<void> advance(
    WidgetTester tester, [
    Duration time = Duration.zero,
  ]) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(time);
    expect(tester.takeException(), isNull);
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() condition, {
    String? reason,
  }) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await advance(tester, const Duration(milliseconds: 20));
    }
    expect(condition(), isTrue, reason: reason);
  }

  Future<T> finish<T>(WidgetTester tester, Future<T> future) async {
    var completed = false;
    late T value;
    Object? failure;
    future.then(
      (result) {
        value = result;
        completed = true;
      },
      onError: (Object error) {
        failure = error;
        completed = true;
      },
    );
    await until(
      tester,
      () => completed,
      reason: 'Original action must complete',
    );
    if (failure != null) throw failure!;
    return value;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await advance(tester, const Duration(milliseconds: 10));
    }
    await until(
      tester,
      () => activities.every((a) => a.held || a.isCompleted),
      reason: 'Unheld fixture actions must complete',
    );
  }

  Future<void> drain(WidgetTester tester) async {
    await until(
      tester,
      () => activities.every((a) => a.isCompleted),
      reason: 'Pending actions must drain before streams and transports reset',
    );
    _all.removeWhere(activities.contains);
    if (identical(current, this)) current = null;
  }

  /// Used only by evidence instrumentation; normal tests emit no audit logs.
  static void auditAssertion(String site) {
    // ignore: avoid_print
    print(
      'VP_H_ASSERT ${jsonEncode({'case': auditCase, 'site': site, 'pending': _all.where((a) => !a.isCompleted).map((a) => a.label).toList()})}',
    );
  }
}
