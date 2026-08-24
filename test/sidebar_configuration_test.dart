import 'package:debrify/models/sidebar_configuration.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
  });

  tearDown(ProfileRuntime.debugReset);

  test('defaults preserve the previously shipped grouped sidebar order', () {
    expect(SidebarConfiguration.defaults().order, <String>[
      'search',
      'home',
      'discover',
      'calendar',
      'downloads',
      'iptv',
      'youtube',
      'cloud',
      'debrify_tv',
      'stremio_tv',
      'addons',
      'settings',
    ]);
  });

  test('custom order is applied after visibility filtering', () {
    final configuration = SidebarConfiguration(
      order: const <String>['settings', 'cloud', 'home'],
    );

    expect(
      configuration.orderVisibleTabs(const <int>[
        MainTab.search,
        MainTab.home,
        MainTab.iptv,
        MainTab.settings,
      ]),
      <int>[MainTab.settings, MainTab.home, MainTab.search, MainTab.iptv],
      reason: 'Cloud stays filtered while all surviving tabs stay reachable',
    );
  });

  test('normalization drops duplicates and appends missing destinations', () {
    final configuration = SidebarConfiguration(
      order: const <String>['home', 'unknown', 'home', 'settings'],
    );

    expect(configuration.order.take(2), <String>['home', 'settings']);
    expect(configuration.order.toSet(), sidebarDestinationById.keys.toSet());
    expect(configuration.order.length, sidebarDestinations.length);
  });

  test('labels are sidebar-only overrides with bounded safe normalization', () {
    final configuration = SidebarConfiguration(
      order: const <String>[],
      labels: const <String, String>{
        'home': '  My   Space  ',
        'settings': 'Settings',
        'unknown': 'Ignored',
      },
    );

    expect(configuration.labelForTab(MainTab.home, 'Home'), 'My Space');
    expect(configuration.labels, <String, String>{'home': 'My Space'});
    expect(SidebarConfiguration.normalizeLabel(''), isNull);
    expect(
      SidebarConfiguration.normalizeLabel(
        'x' * (SidebarConfiguration.maxLabelRunes + 1),
      ),
      isNull,
    );
  });

  test('codec round-trips and rejects malformed or untrusted shapes', () {
    final configuration = SidebarConfiguration(
      order: const <String>['settings', 'home'],
      labels: const <String, String>{'home': 'Start'},
    );
    final encoded = configuration.encode();
    final decoded = SidebarConfiguration.tryDecode(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.order, configuration.order);
    expect(decoded.labels, configuration.labels);
    expect(SidebarConfiguration.tryDecode('{bad json'), isNull);
    expect(
      SidebarConfiguration.tryDecode(
        '{"version":1,"order":["home","home"],"labels":{}}',
      ),
      isNull,
    );
    expect(
      SidebarConfiguration.tryDecode(
        '{"version":1,"order":["home"],"labels":{"home":"  bad  "}}',
      ),
      isNull,
    );
  });

  test(
    'configuration persists independently per profile and resets safely',
    () async {
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
      );
      final first = SidebarConfiguration(
        order: const <String>['settings', 'home'],
        labels: const <String, String>{'home': 'Start'},
      );
      expect(await StorageService.setSidebarConfiguration(first), isTrue);

      ProfileRuntime.publish(
        ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
      );
      expect(
        (await StorageService.getSidebarConfiguration()).isDefault,
        isTrue,
      );

      ProfileRuntime.publish(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 3),
      );
      expect(
        (await StorageService.getSidebarConfiguration()).labelForId('home'),
        'Start',
      );
      expect(await StorageService.resetSidebarConfiguration(), isTrue);
      expect(
        (await StorageService.getSidebarConfiguration()).isDefault,
        isTrue,
      );
    },
  );

  test('configuration is reviewed for profile copy and sanitized backup', () {
    final encoded = SidebarConfiguration(
      order: const <String>['settings', 'home'],
      labels: const <String, String>{'home': 'Start'},
    ).encode();

    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('sidebar_configuration_v1'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'sidebar_configuration_v1',
        encoded,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'sidebar_configuration_v1',
        '{"labels":{"home":"secret\nline"}}',
      ),
      isFalse,
    );
  });
}
