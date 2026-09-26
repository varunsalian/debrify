import 'dart:async';

import 'package:debrify/features/sources/application/saved_sources_dependencies.dart';
import 'package:debrify/features/sources/application/source_binding_controller.dart';
import 'package:debrify/features/sources/application/source_link_dependencies.dart';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/data/saved_sources_repository.dart';
import 'package:debrify/features/sources/data/source_link_copier.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/features/sources/presentation/source_binding_bridge.dart';
import 'package:debrify/features/sources/presentation/source_playback_bridge.dart';
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

class _Settings implements SourceSettingsRepository {
  @override
  bool get isCurrent => true;
  @override
  Future<SourcePrioritySettings> loadPriority() async =>
      SourcePrioritySettings();
  @override
  Future<({bool text, bool logos})> loadAppearance() async =>
      (text: false, logos: false);
}

class _Saved implements SavedSourcesRepository {
  @override
  bool get isCurrent => true;
  @override
  Future<SavedSourcesState> load() async => SavedSourcesState();
  @override
  Future<bool> save(SeriesSource source) async => true;
  @override
  Future<bool> remove(SeriesSource source) async => true;
}

class _Playback extends SourcePlaybackBridge {
  _Playback(this.calls);
  final List<String> calls;
  @override
  bool supportsDownload(Torrent torrent) => true;
  @override
  Future<void> play(
    BuildContext context,
    Torrent torrent, {
    required bool forcePlay,
    required PlaybackMeta meta,
    required List<Torrent> sources,
    required int sourceIndex,
    required String searchKeyword,
  }) async => calls.add('play');
  @override
  Future<void> download(BuildContext context, Torrent torrent) async =>
      calls.add('download');
}

class _Binding extends SourceBindingBridge {
  _Binding(this.calls);
  final List<String> calls;
  @override
  bool get localBindingAvailable => false;
  @override
  Future<bool> pin(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    required SourceBindingWriter saveBinding,
    required bool Function() canContinue,
    String? addonCatalogId,
    String? addonCatalogKey,
  }) async {
    calls.add('pin');
    return false;
  }
}

/// Real Sources view and modal routes, with side effects recorded at DI boundaries.
class ModalSourcesFixture {
  final navigator = GlobalKey<NavigatorState>();
  final dark = ValueNotifier(false);
  final calls = <String>[];
  late MaterialPageRoute<void> origin;

  Future<void> pump(WidgetTester tester, {bool direct = true}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(560, 900));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      dark.dispose();
      ProfileSessionMemory.debugReset();
      await tester.binding.setSurfaceSize(null);
    });
    final torrent = Torrent(
      rowid: 1,
      infohash: 'abcdef',
      name: 'Fixture 1080p',
      source: 'fixture',
      sizeBytes: 0,
      createdUnix: 0,
      seeders: 0,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
      hasRealInfoHash: !direct,
      streamType: direct ? StreamType.directUrl : StreamType.torrent,
      directUrl: direct ? 'https://example.com/fixture' : null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceSettingsRepositoryProvider.overrideWith(
            (ref, key) => _Settings(),
          ),
          savedSourcesRepositoryProvider.overrideWith((ref, key) => _Saved()),
          sourcePlaybackBridgeProvider.overrideWithValue(_Playback(calls)),
          sourceBindingBridgeProvider.overrideWithValue(_Binding(calls)),
          sourceLinkCopierProvider.overrideWithValue(
            SourceLinkCopier(
              isDeferredEpisode: (_) => false,
              resolveEpisode: (_) => throw StateError('Unexpected resolution'),
              writeText: (_) async => calls.add('copy'),
            ),
          ),
        ],
        child: ValueListenableBuilder<bool>(
          valueListenable: dark,
          builder: (_, value, __) => MaterialApp(
            navigatorKey: navigator,
            theme: value ? ThemeData.dark() : ThemeData.light(),
            home: const Scaffold(body: Text('Landing')),
          ),
        ),
      ),
    );
    origin = MaterialPageRoute<void>(
      builder: (_) => AppThemeScope(
        theme: AppThemes.legacy,
        child: sourcesScreenForTesting(
          selection: const AdvancedSearchSelection(
            imdbId: 'tt-modal-fixture',
            title: 'Fixture',
            isSeries: false,
          ),
          meta: const PlaybackMeta(),
          search: (_) async => {
            'torrents': [torrent],
          },
        ),
      ),
    );
    unawaited(navigator.currentState!.push(origin));
    await tester.pumpAndSettle();
  }

  Future<void> retire(WidgetTester tester, String retirement) async {
    if (retirement == 'disposed') {
      navigator.currentState!.removeRoute(origin);
    } else if (retirement == 'profile') {
      ProfileSessionMemory.clearAll();
    }
    await tester.pumpAndSettle();
  }

  Future<void> rebuildModal(WidgetTester tester) async {
    dark.value = !dark.value;
    await tester.pumpAndSettle();
  }
}
