import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/pending_external_action_store.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PendingActionPathProvider extends PathProviderPlatform {
  _PendingActionPathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async =>
      (await Directory('${root.path}/support').create(recursive: true)).path;
}

void main() {
  late Directory root;
  late File storeFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pending-action-test-');
    PathProviderPlatform.instance = _PendingActionPathProvider(root);
    final cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (index) => index),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    storeFile = File(
      '${(await AppStorage.support()).path}/'
      '${PendingExternalActionStore.fileName}',
    );
  });

  tearDown(() async {
    DeviceKeyProvider.debugReset();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('seals, bounds, and consumes pending actions once', () async {
    const secretUrl = 'https://example.test/watch?token=private';
    await PendingExternalActionStore.enqueueAll(<String>[
      secretUrl,
      'magnet:?xt=urn:btih:0123456789abcdef',
      List<String>.filled(16 * 1024 + 1, 'x').join(),
    ]);

    final stored = await storeFile.readAsString();
    expect(stored, isNot(contains(secretUrl)));
    expect(await PendingExternalActionStore.take(), <String>[
      secretUrl,
      'magnet:?xt=urn:btih:0123456789abcdef',
    ]);
    expect(await PendingExternalActionStore.take(), isEmpty);
  });

  test('tampering drops the action and cannot replay it', () async {
    await PendingExternalActionStore.enqueueAll(const <String>[
      'https://example.test/private',
    ]);
    final decoded = jsonDecode(await storeFile.readAsString());
    final entries = (decoded['entries'] as List).cast<Map<String, dynamic>>();
    entries.single['envelope'] = '${entries.single['envelope']}tampered';
    await storeFile.writeAsString(jsonEncode(decoded), flush: true);

    expect(await PendingExternalActionStore.take(), isEmpty);
    expect(await PendingExternalActionStore.take(), isEmpty);
  });
}
