import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalEngineStorage sender;
  late LocalEngineStorage receiver;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('engine-sync-test-');
    sender = LocalEngineStorage.forDirectory(Directory('${root.path}/sender'));
    receiver = LocalEngineStorage.forDirectory(
      Directory('${root.path}/receiver'),
    );
  });
  tearDown(() async => root.delete(recursive: true));

  Future<void> save(
    LocalEngineStorage store,
    String id, [
    String version = 'one',
  ]) => store.saveEngine(
    engineId: id,
    fileName: '$id.yaml',
    yamlContent: 'id: $id\ndisplay_name: $id\nversion: $version\n',
    displayName: id,
  );

  final maps = WebDavSyncIdentityMaps(
    circleToLocalProfiles: {'circle-profile': 'local-profile'},
    circleToLocalResources: {},
  );
  WebDavSyncHotDocument build(
    Map<String, Object> values,
    String device,
    int time, {
    WebDavSyncHotDocument? previous,
  }) => WebDavSyncHotMerge.build(
    WebDavSyncBuildInput(
      circleProfileId: 'circle-profile',
      deviceId: device,
      rawPreferences: values,
      portablePreferences: values,
      identityMaps: maps,
      localNowMs: time,
      clockOffsetMs: 0,
      serverNowMs: time,
      previous: previous,
    ),
  ).document;

  Map<String, Object> materialize(WebDavSyncHotDocument doc) =>
      WebDavSyncHotMerge.materializePreferences(
        document: doc,
        identityMaps: maps,
      );

  test(
    'custom engine install, update, delete and reinstallation round trip',
    () async {
      await save(sender, 'custom');
      var values = await sender.exportSyncDefinitions();
      expect(await receiver.applySyncDefinitions(values), values.keys.toSet());
      expect(
        await receiver.readEngineYaml('custom'),
        await sender.readEngineYaml('custom'),
      );
      expect(await receiver.applySyncDefinitions(values), isEmpty);

      await save(sender, 'custom', 'two');
      values = await sender.exportSyncDefinitions();
      await receiver.applySyncDefinitions(values);
      expect(await receiver.readEngineYaml('custom'), contains('two'));

      await sender.deleteEngine('custom');
      values = await sender.exportSyncDefinitions();
      await receiver.applySyncDefinitions(values);
      expect(await receiver.isEngineImported('custom'), isFalse);
      // Tombstones survive reopening the directory.
      final reopened = LocalEngineStorage.forDirectory(
        Directory('${root.path}/receiver'),
      );
      expect(await reopened.exportSyncDefinitions(), values);
      await save(sender, 'custom', 'three');
      await receiver.applySyncDefinitions(await sender.exportSyncDefinitions());
      expect(await receiver.readEngineYaml('custom'), contains('three'));
    },
  );

  test(
    'an offline unchanged engine cannot resurrect a newer deletion',
    () async {
      await save(sender, 'alpha');
      final old = build(await sender.exportSyncDefinitions(), 'device-a', 1000);
      await sender.deleteEngine('alpha');
      final deleted = build(
        await sender.exportSyncDefinitions(),
        'device-a',
        2000,
        previous: old,
      );
      final unchangedOffline = build(
        materialize(old),
        'device-b',
        3000,
        previous: old,
      );
      final merged = WebDavSyncHotMerge.merge(
        local: unchangedOffline,
        peers: [deleted],
        tombstoneDocuments: [],
        nowMs: 3000,
      ).document;
      await receiver.applySyncDefinitions({
        for (final e in materialize(merged).entries)
          if (e.key.startsWith(LocalEngineStorage.definitionPrefix))
            e.key: e.value,
      });
      expect(await receiver.isEngineImported('alpha'), isFalse);
    },
  );

  test('independent installs merge and same-engine edits converge', () async {
    await save(sender, 'alpha');
    await save(receiver, 'beta');
    final a = build(await sender.exportSyncDefinitions(), 'device-a', 1000);
    final b = build(await receiver.exportSyncDefinitions(), 'device-b', 1000);
    final merged = WebDavSyncHotMerge.merge(
      local: a,
      peers: [b],
      tombstoneDocuments: [],
      nowMs: 2000,
    ).document;
    final values = {
      for (final e in materialize(merged).entries)
        if (e.key.startsWith(LocalEngineStorage.definitionPrefix))
          e.key: e.value,
    };
    await sender.applySyncDefinitions(values);
    expect(
      await sender.getImportedEngineIds(),
      unorderedEquals(['alpha', 'beta']),
    );
    await save(sender, 'alpha', 'new');
    final newer = build(
      await sender.exportSyncDefinitions(),
      'device-a',
      3000,
      previous: merged,
    );
    final left = WebDavSyncHotMerge.merge(
      local: newer,
      peers: [merged],
      tombstoneDocuments: [],
      nowMs: 4000,
    ).document;
    final right = WebDavSyncHotMerge.merge(
      local: merged,
      peers: [newer],
      tombstoneDocuments: [],
      nowMs: 4000,
    ).document;
    expect(materialize(left), materialize(right));
  });

  test(
    'invalid batch cannot partially change the receiver inventory',
    () async {
      await save(receiver, 'existing');
      final before = await receiver.exportSyncDefinitions();
      await save(sender, 'valid');
      final input = await sender.exportSyncDefinitions();
      input[LocalEngineStorage.definitionKey('bad')] = jsonEncode({
        'id': 'bad',
        'deleted': false,
        'name': 'Bad',
        'yaml': 'id: another',
      });
      await expectLater(
        receiver.applySyncDefinitions(input),
        throwsFormatException,
      );
      expect(await receiver.exportSyncDefinitions(), before);
    },
  );

  test('prepared onboarding batch blocks snapshots until rollback', () async {
    await save(sender, 'alpha', 'old');
    final transaction = await sender.saveEnginesAtomically([
      const LocalEngineWrite(
        engineId: 'alpha',
        fileName: 'new.yaml',
        yamlContent: 'id: alpha\nversion: new\n',
        displayName: 'Alpha',
      ),
    ]);
    var snapshotFinished = false;
    final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
      snapshotFinished = true;
      return LocalEngineStorage.forDirectory(
        Directory('${root.path}/sender'),
      ).exportSyncDefinitions();
    });
    await Future<void>.delayed(Duration.zero);
    expect(snapshotFinished, isFalse);
    await transaction!.rollback();
    final values = await snapshot;
    expect(
      jsonDecode(
        values[LocalEngineStorage.definitionKey('alpha')] as String,
      )['yaml'],
      contains('old'),
    );
  });

  test('engine definitions cannot introduce filesystem paths', () async {
    final id = '../../outside';
    final values = {
      LocalEngineStorage.definitionKey(id): jsonEncode({
        'id': id,
        'deleted': false,
        'name': 'Custom',
        'yaml': 'id: ../../outside\n',
      }),
    };
    await receiver.applySyncDefinitions(values);
    final path = await receiver.getEngineFilePath(id);
    expect(File(path!).parent.path, '${root.path}/receiver');
    expect(File('${root.path}/outside').existsSync(), isFalse);
  });
}
