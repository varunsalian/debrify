import 'package:debrify/services/profiles/profile_session_unavailable.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_first_join_resume.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_operation_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late WebDavSyncBindingStore store;
  late WebDavSyncBinding binding;
  late WebDavSyncOperationCoordinator operations;
  late DateTime now;
  late List<String> diagnostics;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 9)),
    );
    store = WebDavSyncBindingStore(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );
    const config = WebDavConfig(
      id: 'server',
      name: 'Server',
      baseUrl: 'https://example.test/dav',
      username: 'alice',
      password: 'secret',
    );
    binding = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(config, 'Family'),
      config: config,
      syncPassphrase: 'circle-secret',
      completeOnboarding: true,
    );
    binding = await store.markRootVerified(
      bindingId: binding.id,
      root: WebDavSyncRootDocument(
        circleId: 'circle-one',
        createdAt: DateTime.utc(2026, 9, 1),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      ),
      markerBytes: const <int>[1, 2, 3],
    );
    binding = await store.setLifecycle(
      binding.id,
      WebDavSyncLifecycle.awaitingAdoption,
    );
    operations = WebDavSyncOperationCoordinator();
    now = DateTime.utc(2026, 9, 3, 10);
    diagnostics = <String>[];
  });

  tearDown(DeviceKeyProvider.debugReset);

  WebDavSyncFirstJoinAutoResume resumePolicy({
    required WebDavSyncFirstJoinConnect connect,
  }) => WebDavSyncFirstJoinAutoResume(
    bindingStore: store,
    operations: operations,
    connect: connect,
    clock: () => now,
    diagnostic: (message, _) => diagnostics.add(message),
  );

  for (final wrapped in [false, true]) {
    test(
      'session interruptions preserve retries and recover wrapped=$wrapped',
      () async {
        var available = false;
        final policy = resumePolicy(
          connect: (id) async {
            if (!available) {
              final error = ProfileSessionUnavailable(
                'Profile session is locked',
              );
              throw wrapped ? WebDavSyncPostHandoffException(error) : error;
            }
            await store.setLifecycle(id, WebDavSyncLifecycle.active);
            await store.promoteStaged(id);
            return (await store.load()).activeBinding!;
          },
        );
        for (var i = 0; i < 7; i++) {
          expect(
            await policy.resumeIfNeeded(reconfigurationPaused: false),
            WebDavSyncFirstJoinAutoResumeOutcome.waiting,
          );
          expect(policy.attemptCount, 0);
          expect((await store.load()).stagedBinding!.errorMessage, isNull);
          expect(
            await policy.retryDelay(),
            WebDavSyncFirstJoinAutoResume.minimumSpacing,
          );
          now = now.add(WebDavSyncFirstJoinAutoResume.minimumSpacing);
        }
        available = true;
        expect(
          await policy.resumeIfNeeded(reconfigurationPaused: false),
          WebDavSyncFirstJoinAutoResumeOutcome.activated,
        );
      },
    );
  }

  test(
    'awaiting adoption arms auto-resume and next foreground completes it',
    () async {
      var publishes = 0;
      var schedulerArms = 0;
      final policy = resumePolicy(
        connect: (bindingId) async {
          publishes++;
          expect(
            (await store.load()).bindings[bindingId]?.completeOnboarding,
            isTrue,
            reason: 'restart must retain the first-run completion intent',
          );
          await store.setLifecycle(bindingId, WebDavSyncLifecycle.active);
          await store.promoteStaged(bindingId);
          return (await store.load()).activeBinding!;
        },
      );

      expect(policy.hasAttemptsRemaining, isTrue);
      final outcome = await policy.resumeIfNeeded(reconfigurationPaused: false);
      if (outcome == WebDavSyncFirstJoinAutoResumeOutcome.activated) {
        schedulerArms++;
      }

      expect(outcome, WebDavSyncFirstJoinAutoResumeOutcome.activated);
      expect((await store.load()).activeBindingId, binding.id);
      expect(publishes, 1);
      expect(schedulerArms, 1);
      expect(diagnostics, <String>[
        'Automatic WebDAV first-sync completion attempt',
      ]);
    },
  );

  test(
    'automatic attempts have a thirty-second floor and stop at five',
    () async {
      var connects = 0;
      final policy = resumePolicy(
        connect: (bindingId) async {
          connects++;
          return (await store.load()).bindings[bindingId]!;
        },
      );

      expect(
        await policy.resumeIfNeeded(reconfigurationPaused: false),
        WebDavSyncFirstJoinAutoResumeOutcome.waiting,
      );
      now = now.add(const Duration(seconds: 29));
      expect(
        await policy.resumeIfNeeded(reconfigurationPaused: false),
        WebDavSyncFirstJoinAutoResumeOutcome.skipped,
      );
      for (var attempt = 2; attempt <= 5; attempt++) {
        now = now.add(const Duration(seconds: 30));
        final outcome = await policy.resumeIfNeeded(
          reconfigurationPaused: false,
        );
        expect(
          outcome,
          attempt == 5
              ? WebDavSyncFirstJoinAutoResumeOutcome.exhausted
              : WebDavSyncFirstJoinAutoResumeOutcome.waiting,
        );
      }
      now = now.add(const Duration(minutes: 1));
      expect(
        await policy.resumeIfNeeded(reconfigurationPaused: false),
        WebDavSyncFirstJoinAutoResumeOutcome.skipped,
      );

      expect(connects, 5);
      expect(policy.attemptCount, 5);
      expect(policy.hasAttemptsRemaining, isFalse);
      expect(diagnostics, hasLength(5));
      expect(diagnostics.toSet(), hasLength(1));
      final persisted = (await store.load()).bindings[binding.id]!;
      expect(persisted.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
      expect(persisted.errorMessage, contains('could not finish'));
    },
  );

  test('offline attempt waits and the next foreground can activate', () async {
    var connects = 0;
    final policy = resumePolicy(
      connect: (bindingId) async {
        connects++;
        if (connects == 1) {
          final error = const WebDavException(
            kind: WebDavErrorKind.network,
            message: 'Could not reach the WebDAV server',
          );
          await store.markError(bindingId, error);
          throw WebDavSyncPostHandoffException(error);
        }
        await store.activateAndPromoteStaged(bindingId);
        return (await store.load()).activeBinding!;
      },
    );

    expect(
      await policy.resumeIfNeeded(reconfigurationPaused: false),
      WebDavSyncFirstJoinAutoResumeOutcome.waiting,
    );
    final waiting = (await store.load()).stagedBinding!;
    expect(waiting.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
    expect(waiting.errorMessage, isNull);
    expect(policy.hasAttemptsRemaining, isTrue);

    now = now.add(WebDavSyncFirstJoinAutoResume.minimumSpacing);
    expect(
      await policy.resumeIfNeeded(reconfigurationPaused: false),
      WebDavSyncFirstJoinAutoResumeOutcome.activated,
    );
    expect(connects, 2);
    expect(
      (await store.load()).activeBinding?.lifecycle,
      WebDavSyncLifecycle.active,
    );
  });

  test('retry delay preserves spacing and stops for terminal state', () async {
    final policy = resumePolicy(
      connect: (_) async => throw const WebDavSyncPostHandoffException(
        WebDavException(
          kind: WebDavErrorKind.timeout,
          message: 'Temporary timeout',
        ),
      ),
    );
    expect(await policy.retryDelay(), Duration.zero);
    expect(
      await policy.resumeIfNeeded(reconfigurationPaused: false),
      WebDavSyncFirstJoinAutoResumeOutcome.waiting,
    );
    expect(
      await policy.retryDelay(),
      WebDavSyncFirstJoinAutoResume.minimumSpacing,
    );
    now = now.add(const Duration(seconds: 10));
    expect(await policy.retryDelay(), const Duration(seconds: 20));
    await store.markAwaitingAdoptionError(
      binding.id,
      StateError('Needs repair'),
    );
    expect(await policy.retryDelay(), isNull);
  });

  test(
    'wrapped authentication errors retain the three-attempt threshold',
    () async {
      final policy = resumePolicy(
        connect: (_) async => throw const WebDavSyncPostHandoffException(
          WebDavException(
            kind: WebDavErrorKind.authentication,
            message: 'Unauthorized',
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        expect(
          await policy.resumeIfNeeded(reconfigurationPaused: false),
          i < 2
              ? WebDavSyncFirstJoinAutoResumeOutcome.waiting
              : WebDavSyncFirstJoinAutoResumeOutcome.failed,
        );
        now = now.add(WebDavSyncFirstJoinAutoResume.minimumSpacing);
      }
      expect(await policy.retryDelay(), isNull);
    },
  );

  test('repeated authentication failure becomes terminal', () async {
    var connects = 0;
    final policy = resumePolicy(
      connect: (bindingId) async {
        connects++;
        final error = const WebDavException(
          kind: WebDavErrorKind.authentication,
          message: 'WebDAV authentication failed',
        );
        await store.markError(bindingId, error);
        throw error;
      },
    );

    for (var attempt = 1; attempt <= 3; attempt++) {
      expect(
        await policy.resumeIfNeeded(reconfigurationPaused: false),
        attempt == 3
            ? WebDavSyncFirstJoinAutoResumeOutcome.failed
            : WebDavSyncFirstJoinAutoResumeOutcome.waiting,
      );
      now = now.add(WebDavSyncFirstJoinAutoResume.minimumSpacing);
    }

    expect(connects, 3);
    expect(policy.hasAttemptsRemaining, isFalse);
    expect(
      (await store.load()).bindings[binding.id]?.lifecycle,
      WebDavSyncLifecycle.error,
    );
    expect(
      await policy.resumeIfNeeded(reconfigurationPaused: false),
      WebDavSyncFirstJoinAutoResumeOutcome.skipped,
    );
  });

  test(
    'non-concurrency failure surfaces and cannot loop automatically',
    () async {
      var connects = 0;
      final policy = resumePolicy(
        connect: (_) async {
          connects++;
          throw StateError('persistent setup failure');
        },
      );

      expect(
        await policy.resumeIfNeeded(reconfigurationPaused: false),
        WebDavSyncFirstJoinAutoResumeOutcome.failed,
      );
      for (var attempt = 0; attempt < 10; attempt++) {
        now = now.add(const Duration(minutes: 1));
        expect(
          await policy.resumeIfNeeded(reconfigurationPaused: false),
          WebDavSyncFirstJoinAutoResumeOutcome.skipped,
        );
      }

      expect(connects, 1);
      expect(policy.attemptCount, lessThanOrEqualTo(5));
      expect(policy.hasAttemptsRemaining, isFalse);
      final persisted = (await store.load()).bindings[binding.id]!;
      expect(persisted.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
      expect(persisted.errorMessage, contains('persistent setup failure'));
    },
  );

  test(
    'manual retry racing auto-resume is serialized without side effects',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var connectorCalls = 0;
      var activeConnectors = 0;
      var maxActiveConnectors = 0;
      var adoptionSideEffects = 0;

      Future<WebDavSyncBinding> connect(String bindingId) async {
        connectorCalls++;
        activeConnectors++;
        if (activeConnectors > maxActiveConnectors) {
          maxActiveConnectors = activeConnectors;
        }
        try {
          final current = (await store.load()).bindings[bindingId]!;
          if (current.lifecycle == WebDavSyncLifecycle.active) return current;
          adoptionSideEffects++;
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
          await store.setLifecycle(bindingId, WebDavSyncLifecycle.active);
          await store.promoteStaged(bindingId);
          return (await store.load()).activeBinding!;
        } finally {
          activeConnectors--;
        }
      }

      final policy = resumePolicy(connect: connect);
      final automatic = policy.resumeIfNeeded(reconfigurationPaused: false);
      await entered.future;
      final manual = operations.run(() => connect(binding.id));
      await Future<void>.delayed(Duration.zero);
      expect(connectorCalls, 1);
      release.complete();

      expect(await automatic, WebDavSyncFirstJoinAutoResumeOutcome.activated);
      await manual;
      expect(connectorCalls, 2);
      expect(maxActiveConnectors, 1);
      expect(adoptionSideEffects, 1);
      expect((await store.load()).activeBindingId, binding.id);
    },
  );

  test('reconfiguration pause suppresses auto-resume', () async {
    var connects = 0;
    final policy = resumePolicy(
      connect: (bindingId) async {
        connects++;
        return (await store.load()).bindings[bindingId]!;
      },
    );

    expect(
      await policy.resumeIfNeeded(reconfigurationPaused: true),
      WebDavSyncFirstJoinAutoResumeOutcome.skipped,
    );
    expect(connects, 0);
    expect(policy.attemptCount, 0);
    expect(diagnostics, isEmpty);
  });
}
