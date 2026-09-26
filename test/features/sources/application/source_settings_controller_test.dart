import 'dart:async';

import 'package:debrify/features/sources/application/source_settings_controller.dart';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
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
}
