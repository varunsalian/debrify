import 'dart:io';

import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final directory = Directory('$root/documents');
    await directory.create(recursive: true);
    return directory.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storageRoot;
  late LocalEngineStorage storage;

  setUpAll(() async {
    storageRoot = await Directory.systemTemp.createTemp('engine_transaction');
    PathProviderPlatform.instance = _FakePathProvider(storageRoot.path);
    storage = LocalEngineStorage.instance;
    await storage.clearAll();
  });

  tearDownAll(() async {
    await storage.clearAll();
    await storageRoot.delete(recursive: true);
  });

  test(
    'a canceled batch restores overwritten engines and removes new ones',
    () async {
      await storage.saveEngine(
        engineId: 'alpha',
        fileName: 'alpha-old.yaml',
        yamlContent: 'id: alpha\nversion: old\n',
        displayName: 'Alpha old',
      );
      final previousMetadata = (await storage.getImportedEngines()).single;
      var cancellationChecks = 0;

      final transaction = await storage.saveEnginesAtomically(
        const <LocalEngineWrite>[
          LocalEngineWrite(
            engineId: 'alpha',
            fileName: 'alpha-new.yaml',
            yamlContent: 'id: alpha\nversion: new\n',
            displayName: 'Alpha new',
          ),
          LocalEngineWrite(
            engineId: 'beta',
            fileName: 'beta.yaml',
            yamlContent: 'id: beta\n',
            displayName: 'Beta',
          ),
        ],
        // First check permits alpha's write; the second simulates Back arriving
        // immediately afterward.
        isCanceled: () => ++cancellationChecks >= 2,
      );

      expect(transaction, isNull);
      expect(await storage.getImportedEngineIds(), <String>['alpha']);
      expect(
        await storage.readEngineYaml('alpha'),
        'id: alpha\nversion: old\n',
      );
      final restoredMetadata = (await storage.getImportedEngines()).single;
      expect(restoredMetadata.fileName, previousMetadata.fileName);
      expect(restoredMetadata.displayName, previousMetadata.displayName);
      expect(restoredMetadata.importedAt, previousMetadata.importedAt);
      expect(
        File(
          '${await storage.getEnginesDirectoryPath()}/alpha-new.yaml',
        ).existsSync(),
        isFalse,
      );
      expect(await storage.isEngineImported('beta'), isFalse);
    },
  );
}
