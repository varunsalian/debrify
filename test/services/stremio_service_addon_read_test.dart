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
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
  });

  test(
    'a same-profile save during a failing decode does not cache an empty list',
    () async {
      // Large enough to decode off the UI isolate, so the read is still
      // decoding while the save lands. It fails only at its final byte.
      final corrupt = '[${List.filled(400000, '"x"').join(',')},';
      SharedPreferences.setMockInitialValues({'stremio_addons_v1': corrupt});
      final stremio = StremioService.instance..invalidateCache();
      final pending = stremio.getAddons();
      // Let the read fetch the stored string and start decoding it.
      await Future<void>.delayed(const Duration(milliseconds: 5));
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
      expect(await pending, isEmpty, reason: 'read the corrupt value');
      expect((await stremio.getAddons()).map((a) => a.id), ['saved']);
    },
  );
}
