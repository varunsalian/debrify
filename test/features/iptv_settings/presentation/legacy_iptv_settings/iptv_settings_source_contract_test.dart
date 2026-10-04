import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_settings_source.dart';

String compact(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=[)\]}])'), '');
void main() {
  final bodies =
      jsonDecode(
            File(
              'test/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test(
    'complete original zone sensitive action and lifecycle bodies remain at production callers',
    () {
      expect(bodies.length, 27);
      for (final entry in bodies.entries) {
        expect(
          compact(iptvSettingsOriginalMember(entry.key)),
          contains(compact(entry.value as String)),
          reason: entry.key,
        );
      }
    },
  );
  test(
    'all 29 single resources three array disposals observer and ticker stay in exact order',
    () {
      final init = iptvSettingsOriginalMember(
        '_IptvSettingsPageState.initState',
      );
      expect(
        compact(init),
        contains('WidgetsBinding.instance.addObserver(this);'),
      );
      expect(compact(init), contains('TabController(length:3,vsync:this)'));
      expect(
        compact(init),
        contains('_tabController.addListener(_onTabChanged)'),
      );
      final dispose = iptvSettingsOriginalMember(
        '_IptvSettingsPageState.dispose',
      );
      expect(RegExp(r'\.dispose\(\)').allMatches(dispose).length, 33);
      expect(
        compact(dispose),
        contains(
          '_tabController.removeListener(_onTabChanged);_tabController.dispose();',
        ),
      );
      expect(
        compact(dispose),
        contains('WidgetsBinding.instance.removeObserver(this);'),
      );
      expect(compact(dispose), endsWith('super.dispose();}'));
    },
  );
  test(
    'full refresh arguments hidden counts synchronous cleanup and no new DB gate',
    () {
      final refresh = iptvSettingsOriginalMember(
        '_IptvSettingsPageState._refreshPlaylistForProfile',
      );
      expect(
        compact(refresh),
        contains(
          'refreshCatalog(playlist,section.\$1,force:true,priority:true)',
        ),
      );
      final removal = iptvSettingsOriginalMember(
        '_IptvSettingsPageState._removePlaylistForProfile',
      );
      expect(
        compact(removal),
        contains(
          'IptvCatalogDb.forgetHiddenGroups(_catalogKeysFor(playlist),origin:WebDavSyncMutationOrigin.user,ownerReferences:_catalogOwnerReferencesFor(playlist));',
        ),
      );
      expect(
        removal,
        isNot(contains('await IptvCatalogDb.forgetHiddenGroups')),
      );
      final load = iptvSettingsOriginalMember(
        '_IptvSettingsPageState._loadSettings',
      );
      expect(
        compact(load),
        contains('_ensureFocusNodes();_reloadHiddenCounts();'),
      );
      for (final body in bodies.keys.map(iptvSettingsOriginalMember)) {
        expect(body, isNot(contains('runExclusive')));
      }
    },
  );
  test(
    'style external write precedes persistence and auto refresh retains both original invocation sites',
    () {
      final style = compact(
        iptvSettingsOriginalMember(
          '_IptvSettingsPageState._setIptvStyleForProfile',
        ),
      );
      expect(
        style,
        contains(
          "LookApplier.noteExternalWrite('iptv_style');awaitIptvAppearanceStorage.setIptvStyle(style);",
        ),
      );
      final page = iptvSettingsOriginalMember(
        '_IptvSettingsPageState._pickAutoRefresh',
      );
      expect(
        compact(page),
        contains('awaitIptvCatalogRefreshService.setIntervalHours(hours);'),
      );
      expect(
        compact(page),
        contains('unawaited(IptvCatalogRefreshService.instance.refreshDue());'),
      );
      final service = File(
        'lib/services/iptv_catalog_refresh_service.dart',
      ).readAsStringSync();
      expect(
        compact(service),
        contains('if(hours!=0)unawaited(instance.refreshDue());'),
      );
    },
  );
}
