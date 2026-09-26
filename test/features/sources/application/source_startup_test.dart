import 'dart:async';

import 'package:debrify/features/sources/application/saved_sources_controller.dart';
import 'package:debrify/features/sources/application/saved_sources_dependencies.dart';
import 'package:debrify/features/sources/application/source_settings_controller.dart';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/application/source_startup.dart';
import 'package:debrify/features/sources/data/saved_sources_repository.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Settings implements SourceSettingsRepository {
  final priority = Completer<SourcePrioritySettings>();
  final appearance = Completer<({bool text, bool logos})>();
  int reads = 0;
  @override
  bool get isCurrent => true;
  @override
  Future<SourcePrioritySettings> loadPriority() {
    reads++;
    return priority.future;
  }

  @override
  Future<({bool text, bool logos})> loadAppearance() => appearance.future;
}

class Saved implements SavedSourcesRepository {
  final result = Completer<SavedSourcesState>();
  int reads = 0;
  @override
  bool get isCurrent => true;
  @override
  Future<SavedSourcesState> load() {
    reads++;
    return result.future;
  }

  @override
  Future<bool> remove(SeriesSource source) =>
      throw StateError('Unexpected write');
  @override
  Future<bool> save(SeriesSource source) =>
      throw StateError('Unexpected write');
}

void main() {
  late Settings settings;
  late Saved saved;
  late ProviderContainer container;
  late SourcesSession session;
  late SourceStartup startup;
  setUp(() {
    ProfileSessionMemory.debugReset();
    addTearDown(ProfileSessionMemory.debugReset);
    settings = Settings();
    saved = Saved();
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: const AdvancedSearchSelection(
        imdbId: 'tt-startup',
        title: 'Fixture',
        isSeries: true,
      ),
    );
    container = ProviderContainer.test(
      overrides: [
        sourceSettingsRepositoryProvider.overrideWith((ref, key) => settings),
        savedSourcesRepositoryProvider.overrideWith((ref, key) => saved),
      ],
    );
    container.listen(sourceSettingsProvider(session), (_, _) {});
    container.listen(savedSourcesProvider(session), (_, _) {});
    startup = container.read(sourceStartupProvider);
    expect(settings.reads, 0);
    expect(saved.reads, 0);
  });

  void finishSettings() {
    settings.priority.complete(
      SourcePrioritySettings(providers: ['preferred']),
    );
    settings.appearance.complete((text: true, logos: false));
  }

  test(
    'startup uses explicitly scoped owners without loading parent state',
    () async {
      final childSettings = Settings();
      final childSaved = Saved();
      final child = ProviderContainer.test(
        parent: container,
        overrides: [
          sourceSettingsRepositoryProvider.overrideWith(
            (ref, key) => childSettings,
          ),
          savedSourcesRepositoryProvider.overrideWith((ref, key) => childSaved),
          sourceSettingsProvider(
            session,
          ).overrideWith(() => SourceSettingsController(session)),
          savedSourcesProvider(
            session,
          ).overrideWith(() => SavedSourcesController(session)),
        ],
      );
      child.listen(sourceSettingsProvider(session), (_, _) {});
      child.listen(savedSourcesProvider(session), (_, _) {});
      final pending = child.read(sourceStartupProvider).load(session);
      expect(settings.reads, 0);
      expect(saved.reads, 0);
      expect(childSettings.reads, 1);
      expect(childSaved.reads, 1);
      childSettings.priority.complete(
        SourcePrioritySettings(providers: ['child']),
      );
      childSettings.appearance.complete((text: true, logos: true));
      childSaved.result.complete(SavedSourcesState(cacheUnavailable: true));
      expect(await pending, isTrue);
      expect(child.read(sourceSettingsProvider(session)).priority.providers, [
        'child',
      ]);
      expect(
        child.read(savedSourcesProvider(session)).cacheUnavailable,
        isTrue,
      );
      expect(
        container.read(sourceSettingsProvider(session)).priority.providers,
        isEmpty,
      );
      expect(
        container.read(savedSourcesProvider(session)).cacheUnavailable,
        isFalse,
      );
    },
  );

  for (final savedFirst in [false, true]) {
    test(
      'ready only after both existing owners load: saved first=$savedFirst',
      () async {
        var finished = false;
        final pending = startup.load(session).then((ready) {
          finished = true;
          return ready;
        });
        expect(settings.reads, 1);
        expect(saved.reads, 1);
        final loaded = SavedSourcesState(cacheUnavailable: true);
        if (savedFirst) {
          saved.result.complete(loaded);
        } else {
          finishSettings();
        }
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        if (savedFirst) {
          finishSettings();
        } else {
          saved.result.complete(loaded);
        }
        expect(await pending, isTrue);
        expect(
          container.read(sourceSettingsProvider(session)).priority.providers,
          ['preferred'],
        );
        expect(container.read(savedSourcesProvider(session)), same(loaded));
      },
    );
  }

  for (final failure in ['appearance', 'saved']) {
    test(
      '$failure error prevents readiness and preserves propagation',
      () async {
        final pending = startup.load(session);
        final assertion = expectLater(pending, throwsStateError);
        settings.priority.complete(SourcePrioritySettings());
        if (failure == 'appearance') {
          settings.appearance.completeError(StateError('fixture'));
          saved.result.complete(SavedSourcesState());
        } else {
          settings.appearance.complete((text: false, logos: false));
          saved.result.completeError(StateError('fixture'));
        }
        await assertion;
      },
    );
  }

  for (final retirement in ['profile', 'scope']) {
    for (final before in [false, true]) {
      test('$retirement retirement before=$before rejects readiness', () async {
        final pending = before ? null : startup.load(session);
        if (retirement == 'profile') {
          ProfileSessionMemory.clearAll();
        } else {
          container.dispose();
        }
        if (before) {
          expect(await startup.load(session), isFalse);
          expect(settings.reads, 0);
          expect(saved.reads, 0);
        } else {
          finishSettings();
          saved.result.complete(SavedSourcesState());
          expect(await pending, isFalse);
        }
      });
    }
  }
}
