import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/transfer/transfer_category.dart';
import 'package:debrify/services/transfer/transfer_category_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(TransferCategoryRegistry.debugReset);

  test('registry order is todays applyBackup sequence', () {
    expect(TransferCategoryRegistry.instance.all.map((c) => c.key).toList(), [
      'realDebrid',
      'torbox',
      'premiumize',
      'allDebrid',
      'pikpak',
      'trakt',
      'simkl',
      'mdblist',
      'searchEngines',
      'addons',
      'webDav',
      'indexerManagers',
      'iptvPlaylists',
      'iptvFavorites',
      'iptvLists',
      'homeCollections',
      'streamBadges',
      'trackingPreferences',
    ]);
  });

  test('router maps derive from the registry', () {
    final registry = TransferCategoryRegistry.instance;
    expect(
      registry.remoteBatchCommands,
      isNot(contains(ConfigCommand.trackingPreferences)),
    );
    expect(registry.remoteBatchCommands, contains(ConfigCommand.streamBadges));
    expect(registry.remoteBatchCommands, contains(ConfigCommand.realDebrid));
    expect(registry.rawStringPayloadToWire.keys.toList(), [
      'realDebridApiKey',
      'torboxApiKey',
      'premiumizeApiKey',
      'allDebridApiKey',
    ]);
    expect(
      registry.encodedPayloadToWire['streamBadges'],
      ConfigCommand.streamBadges,
    );
    expect(
      registry.encodedPayloadToWire.containsKey('homeCollections'),
      isFalse,
    );
    expect(
      registry.encodedPayloadToWire.containsKey('addonManifestUrls'),
      isFalse,
    );
    expect(
      registry.expectedPayloadKeys.containsKey(
        ConfigCommand.trackingPreferences,
      ),
      isFalse,
    );
    expect(
      registry.wireCommandToPayloadKey[ConfigCommand.trackingPreferences],
      'trackingPreferences',
    );
    expect(
      registry.wireCommandToPayloadKey[ConfigCommand.streamBadges],
      'streamBadges',
    );
  });

  test('homeCollections is backup-only; streamBadges is wired', () {
    expect(TransferCategories.homeCollections.wireCommand, isNull);
    expect(
      TransferCategories.streamBadges.wireCommand,
      ConfigCommand.streamBadges,
    );
    expect(TransferCategories.streamBadges.remoteBatch, isTrue);
    expect(TransferCategories.homeCollections.remoteBatch, isFalse);
  });

  test('adding a category registers it end-to-end', () async {
    var applied = false;
    final fake = TransferCategory(
      key: 'fakeCat',
      payloadKey: 'fakeCat',
      wireCommand: 'fake_cat',
      label: 'Fake',
      summarizeLabel: 'Fake thing',
      glyph: TransferCategoryGlyph.extension,
      color: const Color(0xFF123456),
      wireEncoding: TransferWireEncoding.json,
      remoteBatch: true,
      expectedInProfilePayload: true,
      build: (ctx) async {
        ctx.payload['fakeCat'] = <String, dynamic>{'n': 1};
      },
      apply: (ctx) async {
        applied = ctx.map['fakeCat'] is Map;
      },
      count: (map) => map['fakeCat'] is Map ? 1 : 0,
    );
    TransferCategoryRegistry.instance.register(fake);

    expect(TransferCategoryRegistry.instance.all.last.key, 'fakeCat');
    expect(BackupSelection.all().contains(fake), isTrue);
    expect(
      TransferCategoryRegistry.instance.remoteBatchCommands,
      contains('fake_cat'),
    );
    expect(
      TransferCategoryRegistry.instance.encodedPayloadToWire['fakeCat'],
      'fake_cat',
    );
    expect(
      TransferCategoryRegistry.instance.summarizeLabelForWire('fake_cat'),
      'Fake thing',
    );

    final ctx = TransferBuildContext(includeCredentials: true);
    await fake.build(ctx);
    expect(ctx.payload['fakeCat'], {'n': 1});
    expect(fake.count(ctx.payload), 1);

    await BackupRestoreService.applyBackup(<String, dynamic>{
      'fakeCat': <String, dynamic>{'n': 1},
    }, selection: BackupSelection.only({fake}));
    expect(applied, isTrue);
  });

  test(
    'explicit BackupSelection.only does not apply default-on categories',
    () async {
      final report = await BackupRestoreService.applyBackup(<String, dynamic>{
        'homeCollections': [
          {'id': 'col-x', 'title': 'Should skip', 'folders': <Object>[]},
        ],
        'streamBadges': [
          {'id': 'badge-x', 'name': 'Skip', 'json': '{}'},
        ],
        'searchEngineIds': <String>[],
      }, selection: BackupSelection.only({TransferCategories.searchEngines}));
      expect(report.homeCollectionsImported, 0);
      expect(report.streamBadgeSourcesImported, 0);
    },
  );
}
