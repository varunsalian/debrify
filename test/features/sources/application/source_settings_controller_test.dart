import 'dart:async';

import 'package:debrify/features/sources/application/source_settings_controller.dart';
import 'package:debrify/features/sources/application/sources_providers.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Settings implements SourceSettingsRepository {
  @override
  bool isCurrent = true;
  final priority = <Completer<SourcePrioritySettings>>[];
  final appearance = <Completer<({bool text, bool logos})>>[];
  @override
  Future<SourcePrioritySettings> loadPriority() {
    final next = Completer<SourcePrioritySettings>();
    priority.add(next);
    return next.future;
  }

  @override
  Future<({bool text, bool logos})> loadAppearance() {
    final next = Completer<({bool text, bool logos})>();
    appearance.add(next);
    return next.future;
  }
}

void main() {
  late Settings settings;
  late ProviderContainer container;
  late SourceSettingsController controller;
  late ProviderSubscription<SourcePresentationSettings> subscription;
  late SourcesSession session;
  final chosen = SourcePrioritySettings(
    providers: ['engine:b', 'engine:a'],
    aliases: {'B': 'engine:b'},
  );

  setUp(() {
    settings = Settings();
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: const AdvancedSearchSelection(
        imdbId: 'tt-settings',
        title: 'Fixture',
        isSeries: true,
      ),
    );
    container = ProviderContainer.test(
      overrides: [
        sourceSettingsRepositoryProvider.overrideWith((ref, key) => settings),
      ],
    );
    subscription = container.listen(sourceSettingsProvider(session), (_, _) {});
    controller = container.read(sourceSettingsProvider(session).notifier);
  });

  for (final appearanceFirst in [false, true]) {
    test(
      'startup waits for both settings branches, appearance first: $appearanceFirst',
      () async {
        expect(settings.priority, isEmpty);
        expect(settings.appearance, isEmpty);
        var complete = false;
        final pending = controller.load().then((_) => complete = true);
        expect(settings.priority, hasLength(1));
        expect(settings.appearance, hasLength(1));
        if (appearanceFirst) {
          settings.appearance.single.complete((text: true, logos: true));
        } else {
          settings.priority.single.complete(chosen);
        }
        await Future<void>.delayed(Duration.zero);
        expect(complete, isFalse);
        if (appearanceFirst) {
          expect(subscription.read().useAddonText, isTrue);
          settings.priority.single.complete(chosen);
        } else {
          expect(subscription.read().priority, same(chosen));
          settings.appearance.single.complete((text: true, logos: true));
        }
        await pending;
        expect(subscription.read().priority.providers, [
          'engine:b',
          'engine:a',
        ]);
        expect(subscription.read().useAddonText, isTrue);
        expect(subscription.read().showAddonLogos, isTrue);
        expect(
          () => subscription.read().priority.providers.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => subscription.read().priority.aliases.clear(),
          throwsUnsupportedError,
        );
      },
    );
  }

  test('priority failure retains default order and permits startup', () async {
    final pending = controller.load();
    settings.priority.single.completeError(StateError('fixture'));
    settings.appearance.single.complete((text: true, logos: false));
    await pending;
    expect(subscription.read().priority.providers, isEmpty);
    expect(subscription.read().useAddonText, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(settings.priority, hasLength(1));
  });

  test('appearance failure retains existing error propagation', () async {
    final pending = controller.load();
    final assertion = expectLater(pending, throwsStateError);
    settings.appearance.single.completeError(StateError('fixture'));
    settings.priority.single.complete(chosen);
    await assertion;
    expect(subscription.read().priority, same(chosen));
  });

  for (final retirement in [
    'profile',
    'dispose',
    'dependency',
    'replacement',
  ]) {
    test('$retirement rejects both delayed branches', () async {
      final pending = controller.load();
      final oldPriority = settings.priority.single;
      final oldAppearance = settings.appearance.single;
      if (retirement == 'profile') {
        settings.isCurrent = false;
      } else if (retirement == 'dispose') {
        container.dispose();
      } else if (retirement == 'dependency') {
        settings = Settings();
        container.invalidate(sourceSettingsRepositoryProvider(session));
        expect(subscription.read().useAddonText, isFalse);
      } else {
        final newer = controller.load();
        settings.priority.last.complete(SourcePrioritySettings());
        settings.appearance.last.complete((text: false, logos: false));
        await newer;
      }
      oldPriority.complete(chosen);
      oldAppearance.complete((text: true, logos: true));
      await pending;
      if (retirement != 'dispose') {
        expect(subscription.read().priority.providers, isEmpty);
        expect(subscription.read().useAddonText, isFalse);
      }
    });
  }

  test('retired actions perform no reads', () async {
    settings.isCurrent = false;
    await controller.load();
    expect(settings.priority, isEmpty);
    expect(settings.appearance, isEmpty);
  });
  for (final wholeFamily in [false, true]) {
    test(
      'disposed settings scope rejects further reads: family=$wholeFamily',
      () async {
        ProviderContainer scoped(Settings repository) => ProviderContainer.test(
          parent: container,
          overrides: [
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => repository,
            ),
            if (wholeFamily)
              sourceSettingsProvider.overrideWith2(SourceSettingsController.new)
            else
              sourceSettingsProvider(
                session,
              ).overrideWith(() => SourceSettingsController(session)),
          ],
        );
        final firstRepository = Settings();
        final secondRepository = Settings();
        final first = scoped(firstRepository);
        first.listen(sourceSettingsProvider(session), (_, _) {});
        final firstController = first.read(
          sourceSettingsProvider(session).notifier,
        );
        final second = scoped(secondRepository);
        final secondState = second.listen(
          sourceSettingsProvider(session),
          (_, _) {},
        );
        final secondController = second.read(
          sourceSettingsProvider(session).notifier,
        );
        final parentLoad = controller.load();
        final firstLoad = firstController.load();
        final secondLoad = secondController.load();
        first.dispose();
        // An obsolete view callback must not start more IO after its scope closes.
        final retiredLoad = firstController.load();
        expect(firstRepository.priority, hasLength(1));
        expect(firstRepository.appearance, hasLength(1));
        await retiredLoad;
        firstRepository.priority.single.complete(chosen);
        firstRepository.appearance.single.complete((text: true, logos: false));
        await firstLoad;
        expect(subscription.read().priority.providers, isEmpty);
        expect(secondState.read().priority.providers, isEmpty);
        secondRepository.priority.single.complete(chosen);
        secondRepository.appearance.single.complete((text: true, logos: true));
        await secondLoad;
        expect(secondState.read().priority, same(chosen));
        expect(subscription.read().priority.providers, isEmpty);
        settings.priority.single.complete(
          SourcePrioritySettings(providers: ['parent']),
        );
        settings.appearance.single.complete((text: false, logos: true));
        await parentLoad;
        expect(subscription.read().priority.providers, ['parent']);
        expect(secondState.read().priority, same(chosen));
      },
    );

    test(
      'explicit settings scope isolates parent and siblings: family=$wholeFamily',
      () async {
        ProviderContainer scoped(Settings repository) => ProviderContainer.test(
          parent: container,
          overrides: [
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => repository,
            ),
            if (wholeFamily)
              sourceSettingsProvider.overrideWith2(SourceSettingsController.new)
            else
              sourceSettingsProvider(
                session,
              ).overrideWith(() => SourceSettingsController(session)),
          ],
        );
        final firstRepository = Settings();
        final secondRepository = Settings();
        final first = scoped(firstRepository);
        final firstState = first.listen(
          sourceSettingsProvider(session),
          (_, _) {},
        );
        final firstController = first.read(
          sourceSettingsProvider(session).notifier,
        );
        final second = scoped(secondRepository);
        final secondState = second.listen(
          sourceSettingsProvider(session),
          (_, _) {},
        );
        final secondController = second.read(
          sourceSettingsProvider(session).notifier,
        );
        expect(firstController, isNot(same(controller)));
        expect(secondController, isNot(same(firstController)));
        expect(
          container.read(sourceSettingsProvider(session).notifier),
          same(controller),
        );
        expect(
          first.read(sourceSettingsProvider(session).notifier),
          same(firstController),
        );

        final parentLoad = controller.load();
        final firstLoad = firstController.load();
        final secondLoad = secondController.load();
        expect(settings.priority, hasLength(1));
        expect(firstRepository.priority, hasLength(1));
        expect(secondRepository.priority, hasLength(1));
        firstRepository.priority.single.complete(chosen);
        firstRepository.appearance.single.complete((text: true, logos: false));
        await firstLoad;
        expect(firstState.read().priority, same(chosen));
        expect(subscription.read().priority.providers, isEmpty);
        expect(secondState.read().priority.providers, isEmpty);

        first.dispose();
        settings.priority.single.complete(
          SourcePrioritySettings(providers: ['parent']),
        );
        settings.appearance.single.complete((text: false, logos: true));
        secondRepository.priority.single.complete(
          SourcePrioritySettings(providers: ['sibling']),
        );
        secondRepository.appearance.single.complete((text: true, logos: true));
        await Future.wait([parentLoad, secondLoad]);
        expect(subscription.read().priority.providers, ['parent']);
        expect(subscription.read().useAddonText, isFalse);
        expect(secondState.read().priority.providers, ['sibling']);
        expect(secondState.read().useAddonText, isTrue);
      },
    );
  }
}
