import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(() {
    StremioService.instance.debugAddonDecoder = null;
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
  });

  test(
    'a same-profile save during a failing decode does not cache an empty list',
    () async {
      SharedPreferences.setMockInitialValues({'stremio_addons_v1': '[corrupt'});
      final stremio = StremioService.instance..invalidateCache();
      final decoding = Completer<void>();
      final release = Completer<void>();
      stremio.debugAddonDecoder = (source) async {
        decoding.complete();
        await release.future;
        return jsonDecode(source);
      };
      final pending = stremio.getAddons();
      // The read has fetched the corrupt value and is paused in its decode.
      await decoding.future;
      stremio.debugAddonDecoder = null;
      final saved = StremioAddon(
        id: 'saved',
        name: 'Saved',
        manifestUrl: 'https://saved.invalid/manifest.json',
        baseUrl: 'https://saved.invalid',
        resources: ['stream'],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('stremio_addons_v1', jsonEncode([saved.toJson()]));
      // The same-profile addon save moves the inventory generation.
      stremio.invalidateCache();
      release.complete();
      expect(await pending, isEmpty, reason: 'the read decoded the old value');
      expect((await stremio.getAddons()).map((a) => a.id), ['saved']);
    },
  );
}
