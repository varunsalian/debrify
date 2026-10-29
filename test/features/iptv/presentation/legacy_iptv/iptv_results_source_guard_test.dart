import 'package:flutter_test/flutter_test.dart';

import '../../../../support/lib_source.dart';

const _view = 'lib/widgets/iptv/iptv_results_view.dart';
const _iptv = 'lib/features/iptv/presentation/legacy_iptv';

/// The live declaration `owner.name` in `file` (relative to the IPTV slice).
String _at(String file, String owner, String name) => libMember(
  file.startsWith('lib/') ? file : '$_iptv/$file',
  name,
  owner: owner,
);

String _refresh() => _at(
  'iptv_catalog_refresh.dart',
  'IptvCatalogRefresh',
  'applyDbCatalogRefresh',
);

void main() {
  void ordered(String source, List<String> markers) {
    var previous = -1;
    for (final marker in markers) {
      final at = source.indexOf(marker, previous + 1);
      expect(at, greaterThan(previous), reason: 'Missing/reordered: $marker');
      previous = at;
    }
  }

  test('preview floor, native plane and chip retain their paint order', () {
    final stage = _at(
      'iptv_preview_layout.dart',
      'IptvPreviewLayout',
      'buildPreviewStage',
    );
    ordered(stage, [
      'Stack(',
      'IptvStageFloor(',
      'HeroTrailerBackdrop(',
      'IptvStageChip(',
    ]);
    expect(stage, contains('borderRadius: BorderRadius.circular(8)'));
    expect(stage, contains('httpHeaders: ch.playbackHeaders'));
    expect(stage, isNot(contains('child: Opacity(')));
    expect(stage, isNot(contains('child: ColoredBox(')));
    expect(
      _at('iptv_cockpit_stage.dart', 'IptvCockpitStage', 'buildCockpitStage'),
      contains('RepaintBoundary('),
    );
  });

  test('landing seed is armed once and disarmed at both present sites', () {
    final load = _at(
      'iptv_catalog_loading.dart',
      'IptvCatalogLoading',
      'loadPlaylistInner',
    );
    ordered(load, [
      '_catalogState.categoryManuallyChosen = false',
      '_catalogState.landingSeedArmed = true',
    ]);
    for (final name in ['presentCatalog', 'presentDbCatalog']) {
      final present = _at(
        'iptv_catalog_presentation.dart',
        'IptvCatalogPresentation',
        name,
      );
      ordered(present, [
        '_deps.landingCategory(',
        '_catalogState.landingSeedArmed = false',
      ]);
    }
  });

  test('unchanged digest keeps re-pinning before selected-category repair', () {
    final refresh = _refresh();
    ordered(refresh, [
      'fresh.contentDigest == old.contentDigest',
      '!numberingAdded',
      'all.repin(fresh)',
      'filtered.repin(fresh)',
      'if (selectedVanished) _deps.applyFilters()',
      '// Real change.',
    ]);
    expect(refresh, contains('if (_deps.revalidateSuperseded('));
  });

  test(
    'changed digest repairs the same index, attached fallback, then filter',
    () {
      final refresh = _refresh();
      ordered(refresh, [
        'final oldFilteredIndex',
        '_deps.applyFilters();',
        'WidgetsBinding.instance.addPostFrameCallback',
        'final focusLost',
        'oldFilteredIndex.clamp',
        'if (_deps.rowAttached(candidate))',
        'for (final entry in _focusState.cardFocusNodes.entries)',
        '(target ?? _focusState.playlistFilterFocusNode).requestFocus()',
      ]);
      expect(
        refresh.substring(refresh.indexOf('final focusLost')),
        isNot(contains('indexOfInstance(focusedChannel)')),
      );
    },
  );

  test('launcher uses resident instances and materializes its SQL window', () {
    final play = _at('iptv_playback.dart', 'IptvPlayback', 'playChannelInner');
    final resident = _at('iptv_playback.dart', 'IptvPlayback', 'residentDbRow');
    ordered(resident, [
      'await _deps.adoptStartupCategoryValue(channel.group)',
      'final list = _catalogState.filteredChannels',
      'beforePosition: entry.position',
      'final row = list[index]',
      'return row',
    ]);
    expect(
      _at(
        'iptv_startup_resolution.dart',
        'IptvStartupResolution',
        'resolveStartupRow',
      ),
      contains('_deps.residentDbRow('),
    );
    expect(play, contains('source.effectiveSnapshot.page('));
    expect(play, contains('VideoPlayerLauncher.push('));
    expect(play, contains('iptvBrowseProvider: _deps.providePlayerIptvBrowse'));
    final catchup = _at('iptv_catchup.dart', 'IptvCatchup', 'playCatchup');
    expect(catchup, contains('IptvChannel('));
    expect(catchup, contains('VideoPlayerLauncher.push('));
    expect(
      _at(
        'iptv_player_payload.dart',
        'IptvPlayerPayload',
        'playerChannelWithOrigin',
      ),
      contains('attributes:'),
    );
  });

  test(
    'catalog loading rejects stale tickets and keeps deferred cleanup unconditional',
    () {
      final load = _at(
        'iptv_catalog_loading.dart',
        'IptvCatalogLoading',
        'loadPlaylistInner',
      );
      expect(
        load,
        contains(
          'if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;',
        ),
      );
      final start = load.indexOf('final outgoingNodes');
      final end = load.indexOf('if (contentHadFocus)', start);
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final cleanup = load.substring(start, end);
      ordered(cleanup, [
        '_focusState.cardFocusNodes.clear()',
        '_focusState.detachedRows.clear()',
        'WidgetsBinding.instance.addPostFrameCallback',
        'node.dispose()',
      ]);
      expect(cleanup, isNot(contains('if (!mounted) return')));
    },
  );

  test(
    'startup settings chain and cancellation keep their pre-launch guards',
    () {
      ordered(_at(_view, 'IptvResultsViewState', 'initState'), [
        'settingsLoading.loadSettings().then',
        'mounted && _owners.settingsState.settingsError == null',
        'startupLaunch.maybeRunStartupLaunch()',
      ]);
      final startup = _at(
        'iptv_startup_launch.dart',
        'IptvStartupLaunch',
        'maybeRunStartupLaunch',
      );
      ordered(startup, [
        '_deps.resolveStartupRow(',
        'scrollAndFocusStartupRow(',
        '_deps.playChannel(',
      ]);
      expect(startup, contains('_playerState.startupAttempt'));
    },
  );

  test('lazy catalog and stage reads retain their original boundaries', () {
    final list = _at(
      'iptv_catalog_facades.dart',
      'IptvCatalogFacades',
      'makeDbList',
    );
    expect(list, contains('instanceCache: instanceCacheFor(snap)'));
    expect(list, contains('onPageLoaded:'));
    final stage = _at(
      'iptv_cockpit_stage.dart',
      'IptvCockpitStage',
      'buildCockpitStage',
    );
    expect(stage, contains('ValueListenableBuilder<IptvChannel?>('));
    expect(stage, contains('valueListenable: _previewState.previewShown'));
    final content = _at(
      'iptv_content_layout.dart',
      'IptvContentLayout',
      'buildContent',
    );
    expect(content, contains('itemBuilder:'));
    expect(content, contains('_deps.focusNodeFor(channel)'));
    expect(content, contains('onDetached:'));
  });

  test(
    'lifecycle keeps observer, listener, timers and child-resource order',
    () {
      ordered(_at(_view, 'IptvResultsViewState', 'dispose'), [
        'revision.removeListener',
        'recordingState.sourceCountsDebounce?.cancel()',
        'recordingState.androidRecStateDebounce?.cancel()',
        'schedulesRevision.removeListener',
        'removeObserver(this)',
        'selectionState.searchDebounce?.cancel()',
        'selectionState.contentTypeDebounce?.cancel()',
        'statusState.loadTicker?.cancel()',
        'statusState.maintenanceChipTimer?.cancel()',
        'statusState.chipShowTimer?.cancel()',
        'statusState.chipHideTimer?.cancel()',
        'focusState.scrollController.dispose()',
        'previewState.previewShown.dispose()',
        'previewState.previewStreamUrl.dispose()',
        'node.dispose()',
        'super.dispose()',
      ]);
      for (final (file, owner) in [
        ('$_iptv/iptv_stage_floor.dart', '_IptvStageFloorState'),
        (
          'lib/features/iptv/presentation/iptv_stage_chip.dart',
          '_IptvStageChipState',
        ),
      ]) {
        ordered(_at(file, owner, 'dispose'), [
          '_ctrl.dispose()',
          'super.dispose()',
        ]);
      }
      ordered(
        _at(
          'lib/features/iptv/presentation/spotlight_category_picker_dialog.dart',
          '_SpotlightCategoryPickerDialogState',
          'dispose',
        ),
        [
          '_scrollController.dispose()',
          '_selectedFocusNode.dispose()',
          'super.dispose()',
        ],
      );
    },
  );
}
