import 'dart:async';

import 'package:debrify/services/webdav_sync/webdav_sync_operation_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'operations serialize while nested completion remains re-entrant',
    () async {
      final coordinator = WebDavSyncOperationCoordinator();
      final firstMayFinish = Completer<void>();
      final firstStarted = Completer<void>();
      final events = <String>[];

      final first = coordinator.run(() async {
        events.add('first-start');
        firstStarted.complete();
        await coordinator.run(() async => events.add('nested'));
        await firstMayFinish.future;
        events.add('first-end');
      });
      await firstStarted.future;
      final second = coordinator.run(() async => events.add('second'));
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>['first-start', 'nested']);
      firstMayFinish.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(events, <String>['first-start', 'nested', 'first-end', 'second']);
    },
  );

  test(
    'retirement apply is serialized against a concurrent cycle signal',
    () async {
      final coordinator = WebDavSyncOperationCoordinator();
      final retirementStarted = Completer<void>();
      final finishRetirement = Completer<void>();
      final events = <String>[];

      final retirement = serializeWebDavSyncPendingActiveProfileApply(
        operations: coordinator,
        apply: () async {
          events.add('retirement-start');
          retirementStarted.complete();
          await finishRetirement.future;
          events.add('retirement-end');
        },
      );
      await retirementStarted.future;
      final cycle = coordinator.run(() async => events.add('cycle'));
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>['retirement-start']);
      finishRetirement.complete();
      await Future.wait(<Future<void>>[retirement, cycle]);
      expect(events, <String>['retirement-start', 'retirement-end', 'cycle']);
    },
  );
}
