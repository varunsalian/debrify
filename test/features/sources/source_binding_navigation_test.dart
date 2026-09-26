import 'dart:async';

import 'package:debrify/features/sources/application/source_binding_controller.dart';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/application/saved_sources_dependencies.dart';
import 'package:debrify/features/sources/data/saved_sources_repository.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings implements SourceSettingsRepository {
  @override
  bool get isCurrent => true;
  @override
  Future<SourcePrioritySettings> loadPriority() async =>
      SourcePrioritySettings();
  @override
  Future<({bool text, bool logos})> loadAppearance() async =>
      (text: false, logos: false);
}

class Repository implements SavedSourcesRepository {
  var saves = 0;
  var loads = 0;
  var acceptsSave = true;
  @override
  bool get isCurrent => true;
  @override
  Future<SavedSourcesState> load() async {
    loads++;
    return SavedSourcesState();
  }

  @override
  Future<bool> remove(SeriesSource source) async => true;
  @override
  Future<bool> save(SeriesSource source) async {
    saves++;
    return acceptsSave;
  }
}

class PendingPicker extends SourceBindingBridge {
  final selected = Completer<void>();
  var started = false;
  @override
  bool get localBindingAvailable => true;
  @override
  Future<bool> pinLocal(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    required SourceBindingWriter saveBinding,
    required bool Function() canContinue,
    required String title,
    String? year,
  }) async {
    started = true;
    await selected.future;
    return saveBinding(
      SeriesSource(
        torrentHash: '',
        torrentName: title,
        debridService: SeriesSource.localService,
        debridTorrentId: '',
        boundAt: 1,
        localPath: '/fixture/movie.mkv',
      ),
    );
  }
}

void main() {
  for (final scenario in [
    'current',
    'covered',
    'source_removed',
    'profile_retired',
    'save_rejected',
    'normal_mode',
  ]) {
    testWidgets('Sources binding completion owns its route: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(ProfileSessionMemory.debugReset);
      final navigator = GlobalKey<NavigatorState>();
      final bridge = PendingPicker();
      final repository = Repository()
        ..acceptsSave = scenario != 'save_rejected';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceBindingBridgeProvider.overrideWithValue(bridge),
            savedSourcesRepositoryProvider.overrideWith(
              (ref, session) => repository,
            ),
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, session) => Settings(),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Original page')),
          ),
        ),
      );
      final picker = MaterialPageRoute<void>(
        builder: (_) => AppThemeScope(
          theme: AppThemes.legacy,
          child: sourcesScreenForTesting(
            bindMode: scenario != 'normal_mode',
            selection: const AdvancedSearchSelection(
              imdbId: 'tt-binding-route',
              title: 'Fixture',
              isSeries: false,
            ),
            meta: const PlaybackMeta(),
            search: (_) async => {'torrents': <Torrent>[]},
          ),
        ),
      );
      unawaited(navigator.currentState!.push(picker));
      await tester.pumpAndSettle();
      final initialLoads = repository.loads;
      await tester.tap(find.byTooltip('Pin an on-device file or folder'));
      await tester.pump();
      expect(bridge.started, isTrue);
      MaterialPageRoute<void>? incoming;
      if (scenario == 'covered' || scenario == 'source_removed') {
        if (scenario == 'source_removed') {
          navigator.currentState!.removeRoute(picker);
        }
        incoming = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Incoming page')),
        );
        unawaited(navigator.currentState!.push(incoming));
        await tester.pumpAndSettle();
      } else if (scenario == 'profile_retired') {
        ProfileSessionMemory.clearAll();
      }
      bridge.selected.complete();
      await tester.pumpAndSettle();
      final retired =
          scenario == 'source_removed' || scenario == 'profile_retired';
      final success = !retired && scenario != 'save_rejected';
      expect(repository.saves, retired ? 0 : 1);
      expect(repository.loads, initialLoads + (success ? 1 : 0));
      final closesPicker = success && scenario != 'normal_mode';
      expect(picker.isActive, !closesPicker && scenario != 'source_removed');
      if (incoming != null) {
        expect(incoming.isCurrent, isTrue);
        expect(find.text('Incoming page'), findsOneWidget);
      } else if (scenario == 'current') {
        expect(find.text('Original page'), findsOneWidget);
        expect(navigator.currentState!.canPop(), isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
