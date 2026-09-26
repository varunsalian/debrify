import 'dart:async';
import 'package:debrify/features/sources/application/source_retry_controller.dart';
import 'package:debrify/features/sources/application/source_search_dependencies.dart';
import 'package:debrify/features/sources/data/service_source_search_repository.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const selection = AdvancedSearchSelection(
  imdbId: 'tt-fixture',
  title: 'Fixture',
  isSeries: true,
);
AddonSearchStatus status(String key) => AddonSearchStatus(
  addonId: 'shared-id',
  addonKey: key,
  name: key,
  sourceKey: key,
  count: 0,
  error: 'timeout',
);

void main() {
  late ProviderContainer container;
  late SourceRetryController controller;
  late ProviderSubscription<Set<String>> subscription;
  late SourcesSession session;
  late List<(String, Completer<List<Torrent>>)> calls;
  setUp(() {
    calls = [];
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: selection,
    );
    container = ProviderContainer.test(
      overrides: [
        sourceSearchRepositoryProvider.overrideWith(
          (ref, key) => ServiceSourceSearchRepository(
            owner: key.owner,
            retryAddon:
                ({
                  required addonId,
                  required type,
                  required imdbId,
                  season,
                  episode,
                  required timeout,
                  required preserveOrder,
                  originVideoId,
                }) {
                  final result = Completer<List<Torrent>>();
                  calls.add((addonId, result));
                  return result.future;
                },
          ),
        ),
      ],
    );
    subscription = container.listen(sourceRetryProvider(session), (_, _) {});
    controller = container.read(sourceRetryProvider(session).notifier);
  });

  test(
    'explicit retries dedupe one configuration and allow other configurations',
    () async {
      expect(calls, isEmpty);
      final first = controller.retry(selection, status('one'));
      expect(await controller.retry(selection, status('one')), isNull);
      final second = controller.retry(selection, status('two'));
      expect(calls.map((call) => call.$1), ['one', 'two']);
      expect(subscription.read(), {'one', 'two'});
      expect(() => subscription.read().clear(), throwsUnsupportedError);
      calls.first.$2.complete([]);
      expect(await first, isEmpty);
      expect(subscription.read(), {'two'});
      calls.last.$2.complete([]);
      expect(await second, isEmpty);
      expect(subscription.read(), isEmpty);
    },
  );

  test('old retry cannot clear same-key retry from a newer search', () async {
    final old = controller.retry(selection, status('one'));
    controller.beginSearch();
    final next = controller.retry(selection, status('one'));
    calls.first.$2.complete([]);
    expect(await old, isNull);
    expect(subscription.read(), {'one'});
    calls.last.$2.complete([]);
    expect(await next, isEmpty);
    expect(subscription.read(), isEmpty);
  });

  test('failure clears busy state without automatic retry', () async {
    final pending = controller.retry(selection, status('one'));
    calls.single.$2.completeError(StateError('fixture'));
    expect(await pending, isNull);
    expect(subscription.read(), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(1));
  });

  for (final wholeFamily in [false, true]) {
    test(
      'explicit retry scopes isolate pending work: family=$wholeFamily',
      () async {
        ProviderContainer scoped() => ProviderContainer.test(
          parent: container,
          overrides: [
            sourceSearchRepositoryProvider.overrideWith(
              (ref, key) => container.read(sourceSearchRepositoryProvider(key)),
            ),
            if (wholeFamily)
              sourceRetryProvider.overrideWith2(SourceRetryController.new)
            else
              sourceRetryProvider(
                session,
              ).overrideWith(() => SourceRetryController(session)),
          ],
        );
        final first = scoped();
        final firstState = first.listen(
          sourceRetryProvider(session),
          (_, _) {},
        );
        final firstController = first.read(
          sourceRetryProvider(session).notifier,
        );
        final second = scoped();
        final secondState = second.listen(
          sourceRetryProvider(session),
          (_, _) {},
        );
        final secondController = second.read(
          sourceRetryProvider(session).notifier,
        );
        expect(firstController, isNot(same(controller)));
        expect(secondController, isNot(same(firstController)));
        expect(
          container.read(sourceRetryProvider(session).notifier),
          same(controller),
        );
        expect(
          first.read(sourceRetryProvider(session).notifier),
          same(firstController),
        );

        final parentRetry = controller.retry(selection, status('same-key'));
        final firstRetry = firstController.retry(selection, status('same-key'));
        final secondRetry = secondController.retry(
          selection,
          status('same-key'),
        );
        expect(calls, hasLength(3));
        expect(subscription.read(), {'same-key'});
        expect(firstState.read(), {'same-key'});
        expect(secondState.read(), {'same-key'});
        first.dispose();
        calls[1].$2.complete([]);
        expect(await firstRetry, isNull);
        expect(subscription.read(), {'same-key'});
        expect(secondState.read(), {'same-key'});
        calls[2].$2.complete([]);
        expect(await secondRetry, isEmpty);
        expect(secondState.read(), isEmpty);
        expect(subscription.read(), {'same-key'});
        calls[0].$2.complete([]);
        expect(await parentRetry, isEmpty);
        expect(subscription.read(), isEmpty);
      },
    );
  }

  for (final retire in ['profile', 'dispose', 'dependency']) {
    for (final failure in [false, true]) {
      test('$retire rejects a late ${failure ? 'error' : 'result'}', () async {
        final pending = controller.retry(selection, status('one'));
        if (retire == 'profile') {
          ProfileSessionMemory.clearAll();
        } else if (retire == 'dispose') {
          container.dispose();
        } else {
          container.invalidate(sourceSearchRepositoryProvider(session));
          expect(subscription.read(), isEmpty);
        }
        if (failure) {
          calls.single.$2.completeError(StateError('fixture'));
        } else {
          calls.single.$2.complete([]);
        }
        expect(await pending, isNull);
        if (retire == 'dependency') expect(subscription.read(), isEmpty);
      });
    }
  }
}
