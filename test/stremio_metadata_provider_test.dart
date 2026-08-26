import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/addons/addon_hub_screen.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StremioAddon metaAddon({
  required String id,
  required String name,
  required String url,
}) => StremioAddon(
  id: id,
  name: name,
  manifestUrl: '$url/manifest.json',
  baseUrl: url,
  resources: const ['meta'],
  types: const ['movie', 'series'],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StremioService.instance.invalidateCache();
  });

  test('recommended metadata policy chooses Cinemeta over installed order', () {
    final iptv = metaAddon(
      id: 'iptv.meta',
      name: 'IPTV Metadata',
      url: 'https://iptv.test',
    );
    final cinemeta = metaAddon(
      id: 'com.linvo.cinemeta',
      name: 'Cinemeta',
      url: 'https://cinemeta.test',
    );

    expect(
      StremioService.metadataCandidatesForPreference([iptv, cinemeta], null),
      [cinemeta],
    );
  });

  test('explicit provider is strict and Automatic preserves addon order', () {
    final first = metaAddon(
      id: 'first.meta',
      name: 'First',
      url: 'https://first.test',
    );
    final second = metaAddon(
      id: 'second.meta',
      name: 'Second',
      url: 'https://second.test',
    );

    expect(
      StremioService.metadataCandidatesForPreference([
        first,
        second,
      ], StremioService.metadataProviderValue(second)),
      [second],
    );
    expect(
      StremioService.metadataCandidatesForPreference([
        first,
        second,
      ], StremioService.automaticMetadataProvider),
      [first, second],
    );
  });

  test('metadata provider preference persists', () async {
    const value = StremioService.automaticMetadataProvider;
    expect(
      await StremioService.instance.getMetadataProviderPreference(),
      isNull,
    );

    await StremioService.instance.setMetadataProviderPreference(value);

    expect(
      await StremioService.instance.getMetadataProviderPreference(),
      value,
    );
  });

  test('metadata provider preference is safe to export without URLs', () {
    final provider = metaAddon(
      id: 'private.meta',
      name: 'Private',
      url: 'https://private.test/config-token',
    );
    final value = StremioService.metadataProviderValue(provider);

    expect(value, hasLength(64));
    expect(value, isNot(contains('config-token')));
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'stremio_metadata_provider_v1',
        value,
      ),
      isTrue,
    );
  });

  test('metadata provider identity survives resource ID replacement', () {
    final beforeRestore = metaAddon(
      id: 'private.meta',
      name: 'Private',
      url: 'https://private.test/config-token',
    ).copyWith(connectionResourceId: 'resource-before-restore');
    final afterRestore = metaAddon(
      id: 'private.meta',
      name: 'Private',
      url: 'https://private.test/config-token',
    ).copyWith(connectionResourceId: 'resource-after-restore');

    expect(
      StremioService.metadataProviderValue(afterRestore),
      StremioService.metadataProviderValue(beforeRestore),
    );
    expect(
      afterRestore.sourceBindingKey,
      isNot(beforeRestore.sourceBindingKey),
    );
  });

  testWidgets('Addons shows the responsive metadata selector', (tester) async {
    final iptv = metaAddon(
      id: 'iptv.meta',
      name: 'IPTV Metadata',
      url: 'https://iptv.test',
    );
    final cinemeta = metaAddon(
      id: 'com.linvo.cinemeta',
      name: 'Cinemeta',
      url: 'https://cinemeta.test',
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([iptv.toJson(), cinemeta.toJson()]),
    });
    StremioService.instance.invalidateCache();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: const AddonHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Metadata provider'), findsOneWidget);
    expect(find.text('Cinemeta · Recommended'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
