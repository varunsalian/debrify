import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../support/addon_hub_source.dart';

void main() {
  final frozen =
      jsonDecode(
            File(
              'test/features/addon_hub/presentation/legacy_addon_hub/addon_hub_original_tokens.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final groups = <String, List<String>>{
    'whole State lifecycle and 15 ordered cleanup statements': [
      'initState',
      'dispose',
    ],
    'original loads revision guards and stale known-engine assignment': [
      '_loadInstalled',
      '_loadMarket',
      '_onEnginesChanged',
      '_loadEngines',
    ],
    'three separate engine sequences and blocking root navigator protocol': [
      '_installEngine',
      '_deleteEngine',
      '_importEngineFromFile',
      '_showBlockingProgress',
      '_dismissBlockingProgress',
    ],
    'addon operation arguments confirmations and swallowed prefix rules': [
      '_installFromMarket',
      '_configureInBrowser',
      '_addByUrl',
      '_importJson',
      '_updateAll',
      '_deleteAll',
      '_toggleAddon',
      '_renameAddon',
      '_updateAddon',
      '_removeAddon',
    ],
    'optimistic metadata captured rollback and provider order': [
      '_setMetadataProvider',
      '_buildMetadataProviderSetting',
    ],
    'captured sheet snapshot actions and dialog ctx': [
      '_showOptions',
      '_showDetails',
      '_showActionsMenu',
    ],
    'D-pad KeyDown Repeat band policy and focus fallbacks': [
      '_onPageKey',
      '_hasLeftNeighbour',
      '_focusFirstRow',
      '_toggleSearch',
      '_buildFilterBar',
      '_buildSearchField',
    ],
    'installed and market ordering filtering nav-index pool builder': [
      '_buildInstalledList',
      '_buildMarketListBody',
      '_isInstalled',
      '_matchesFilters',
    ],
  };
  for (final group in groups.entries) {
    test(group.key, () {
      for (final name in group.value) {
        final key = '_AddonHubScreenState.$name';
        expect(addonHubOriginalTokens(key), frozen[key], reason: key);
      }
    });
  }
  test(
    'grow-only row pool and whole focus widgets retain repeat and scroll behavior',
    () {
      for (final name in [
        '_RowNav',
        '_FocusCard',
        '_FocusCardState',
        '_MarketButton',
        '_MarketButtonState',
        '_OptionTile',
        '_OptionTileState',
        '_HubActionButton',
        '_HubActionButtonState',
        '_HubDialogButton',
        '_HubDialogButtonState',
        '_centerInScrollable',
      ]) {
        expect(addonHubOriginalTokens(name), frozen[name], reason: name);
      }
    },
  );
  test(
    'rename remains TextFormField and both TV fields never assign node onKeyEvent',
    () {
      final source = [
        File('lib/screens/addons/addon_hub_screen.dart').readAsStringSync(),
        for (final file
            in Directory('lib/features/addon_hub')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')))
          file.readAsStringSync(),
      ].join('\n');
      expect(RegExp(r'\bTextFormField\(').allMatches(source).length, 1);
      expect(RegExp(r'\bTvTextField\(').allMatches(source).length, 2);
      expect(RegExp(r'\.onKeyEvent\s*=').hasMatch(source), isFalse);
      expect(RegExp(r'\bTextField\(').hasMatch(source), isFalse);
    },
  );
}
