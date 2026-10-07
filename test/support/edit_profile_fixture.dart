import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/edit_profile_screen.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Holds AFTER the real PIN write; subsequent editor refresh is observable.
class EditProfilePins extends ProfilePinService {
  EditProfilePins(ProfileRegistry registry)
    : super(registry: registry, params: const PinKdfParams(iterations: 1));
  Completer<void>? release;
  bool written = false;
  bool failSet = false;
  bool failRemove = false;
  final targets = <String>[];
  @override
  Future<String> setPinAsAdmin({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
    required String pin,
  }) async {
    targets.add(targetProfileId);
    if (failSet) throw StateError('fixture PIN failure');
    final code = await super.setPinAsAdmin(
      actor: actor,
      targetProfileId: targetProfileId,
      pin: pin,
    );
    written = true;
    await release?.future;
    return code;
  }

  @override
  Future<void> removePinAsAdmin({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
  }) async {
    if (failRemove) throw StateError('fixture reset failure');
    return super.removePinAsAdmin(
      actor: actor,
      targetProfileId: targetProfileId,
    );
  }
}

class EditProfilePicker extends FilePicker {
  Future<FilePickerResult?> Function()? response;
  FileType? type;
  bool? withData;
  int calls = 0;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.type = type;
    this.withData = withData;
    calls++;
    return response?.call();
  }
}

class EditProfileFixture {
  late Directory root;
  late ProfileRegistry registry;
  late UserProfile admin;
  late ProfileAuthorizationContext authorization;
  late EditProfilePins pins;
  final picker = EditProfilePicker();
  late FilePicker oldPicker;
  final navigator = GlobalKey<NavigatorState>();
  final capture = GlobalKey();
  bool television = false;
  bool popped = false;
  Object? result;
  int reloads = 0;

  Future<void> open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
    root = await Directory.systemTemp.createTemp('edit-profile-original-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    registry = await ProfileRegistry.open(
      path: p.join(root.path, 'profiles.db'),
    );
    admin = await registry.createProfile(
      name: 'Managing Admin',
      role: UserProfileRole.admin,
      setupComplete: true,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(scope(admin, epoch: 1));
    final cipher = MemoryDeviceSecretCipher(List<int>.filled(32, 11));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    authorization = await ProfileAuthorizationContext.capture(registry);
    pins = EditProfilePins(registry);
    try {
      oldPicker = FilePicker.platform;
    } catch (_) {
      // Flutter tests do not register the native picker plugin.
      oldPicker = EditProfilePicker();
    }
    FilePicker.platform = picker;
    MainPageBridge.reloadProfilePolicy = () => reloads++;
    ProfileAvatarPolicy.debugSetUserImagesSupported(true);
    LocalEngineStorage.instance.resetProfileScope();
  }

  ProfileScope scope(UserProfile profile, {int epoch = 0}) => ProfileScope(
    profileId: profile.id,
    dataGeneration: profile.visibleDataGeneration,
    sessionEpoch: epoch,
  );
  Future<UserProfile> profile(
    String name, {
    UserProfileRole role = UserProfileRole.member,
    ProfilePolicy? policy,
    String avatar = 'person',
    bool lock = false,
    int? timeout,
  }) async {
    final actor = ProfileRuntime.isProfileCommitted
        ? await ProfileAuthorizationContext.capture(registry)
        : null;
    return registry.createProfile(
      name: name,
      role: role,
      policy: policy,
      avatarKey: avatar,
      lockOnResume: lock,
      inactivityTimeoutMinutes: timeout,
      setupComplete: true,
      actingProfileId: actor?.profileId,
      actingAuthorizationRevision: actor?.authorizationRevision,
      actingSessionEpoch: actor?.sessionEpoch,
    );
  }

  Future<void> refreshActor() async {
    authorization = await ProfileAuthorizationContext.capture(registry);
  }

  Future<void> activate(UserProfile profile) async {
    await registry.setActiveProfile(profile.id);
    final fresh = (await registry.getProfile(profile.id))!;
    ProfileRuntime.publish(
      scope(fresh, epoch: ProfileRuntime.capture().sessionEpoch + 1),
    );
  }

  Future<ConnectionResource> resource(
    String label, {
    ConnectionResourceType type = ConnectionResourceType.webDav,
  }) async {
    await refreshActor();
    final r =
        await ConnectionResourceService(
          registry: registry,
          cipher: DeviceKeyProvider.cipher,
        ).create(
          context: authorization,
          type: type,
          label: label,
          publicConfig: const {},
          secretConfig: const {'fixtureSecret': 'original-test-only'},
        );
    await refreshActor();
    final service = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    for (final profile in await registry.listProfiles()) {
      if (profile.id == r.ownerProfileId) continue;
      if (await registry.getGrant(profile.id, r.id) == null) continue;
      await service.revokeGrant(
        actor: authorization,
        targetProfileId: profile.id,
        resourceId: r.id,
      );
      await refreshActor();
    }
    return r;
  }

  Future<void> grant(
    UserProfile target,
    ConnectionResource resource,
    Set<ResourcePermission> permissions,
  ) async {
    await refreshActor();
    await ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    ).grant(
      actor: authorization,
      targetProfileId: target.id,
      resourceId: resource.id,
      permissions: permissions,
    );
    await refreshActor();
  }

  Future<void> engine(UserProfile target, String id, String name) async {
    final dir = Directory(
      p.join(scope(target).storageDirectory(root, 'documents').path, 'engines'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'metadata.json'));
    final records = await file.exists()
        ? Map<String, dynamic>.from(
            (jsonDecode(await file.readAsString()) as Map)['engines'] as Map,
          )
        : <String, dynamic>{};
    await File(
      p.join(dir.path, '$id.yaml'),
    ).writeAsString('name: $name\nsource: original_$id\n');
    records[id] = {
      'id': id,
      'fileName': '$id.yaml',
      'displayName': name,
      'importedAt': '2026-01-01T00:00:00.000Z',
      'icon': null,
    };
    await file.writeAsString(
      jsonEncode({
        'version': '1.0',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'engines': records,
      }),
    );
  }

  Future<Map<String, dynamic>> avatarIntents() async {
    final slots = <Map<String, dynamic>>[];
    for (final suffix in ['', '.next']) {
      final file = File('${root.path}/profile-avatar-mutations-v1.json$suffix');
      if (await file.exists()) {
        slots.add(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      }
    }
    slots.sort(
      (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
    );
    return slots.isEmpty
        ? {}
        : Map<String, dynamic>.from(slots.last['profiles'] as Map);
  }

  Future<Map<String, String>> engines(String id) async {
    final target = (await registry.getProfile(id))!;
    final dir = Directory(
      p.join(scope(target).storageDirectory(root, 'documents').path, 'engines'),
    );
    final file = File(p.join(dir.path, 'metadata.json'));
    if (!await file.exists()) return {};
    final records =
        (jsonDecode(await file.readAsString()) as Map)['engines'] as Map;
    return {
      for (final entry in records.entries)
        entry.key as String: await File(
          p.join(dir.path, (entry.value as Map)['fileName'] as String),
        ).readAsString(),
    };
  }

  Future<void> mount(
    WidgetTester t, {
    UserProfile? target,
    Size size = const Size(1100, 1600),
    Future<(List<ConnectionResource>, List<ProfileEngineAssignment>)>
    Function()?
    loader,
    bool wait = true,
  }) async {
    PlatformUtil.debugSetAndroidTvCached(television);
    await t.binding.setSurfaceSize(size);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en', 'US'),
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: 'Inter',
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: RepaintBoundary(key: capture, child: child!),
        ),
        home: const Scaffold(body: Text('ORIGINAL home')),
      ),
    );
    navigator.currentState!
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => EditProfileScreen(
              registry: registry,
              pins: pins,
              authorization: authorization,
              profile: target,
              setupOptionsLoader: loader,
            ),
          ),
        )
        .then((value) {
          popped = true;
          result = value;
        });
    await t.pump();
    for (var i = 0; i < 6; i++) {
      await settle(t);
    }
    if (wait) {
      if (television) await section(t, 'access');
      await until(
        t,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      if (television) await section(t, 'profile');
    }
  }

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    final messages = <String>{};
    for (var i = 0; i < 250 && !ready(); i++) {
      await settle(t);
      for (final element in find.byType(SnackBar).evaluate()) {
        final content = (element.widget as SnackBar).content;
        if (content is Text && content.data != null) {
          messages.add(content.data!);
        }
      }
    }
    expect(
      ready(),
      isTrue,
      reason:
          'ORIGINAL fixture operation completed; snackbars: $messages; PIN targets: ${pins.targets}; written: ${pins.written}; visible: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(" | ")}',
    );
    await t.pump();
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pump();
    await t.tap(finder);
    await settle(t);
  }

  Future<void> section(WidgetTester t, String name) async {
    await tap(t, find.byKey(ValueKey('tv-profile-tab-$name')));
    if (name == 'access') {
      await until(
        t,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
    }
  }

  Future<void> name(WidgetTester t, String value) async {
    await t.enterText(find.byType(TextField).first, value);
    await t.pump();
  }

  Future<void> pin(WidgetTester t, String value) async {
    if (television) {
      await section(t, 'lock');
    }
    final field = find.byType(TextField).last;
    await t.ensureVisible(field);
    await t.enterText(field, value);
    await t.pump();
  }

  VoidCallback saveCallback(WidgetTester t) {
    final button = find.byWidgetPredicate(
      (w) =>
          w is TextButton &&
          w.child is Text &&
          (w.child as Text).data == 'Save',
    );
    if (!television) {
      return t.widget<TextButton>(button).onPressed!;
    }
    final dynamic rail = t.widget(
      find.byKey(const ValueKey('tv-profile-save')),
    );
    return rail.onPressed as VoidCallback;
  }

  Future<void> save(WidgetTester t) async {
    await t.runAsync(() async {
      saveCallback(t)();
    });
    await settle(t);
  }

  CheckboxListTile checkbox(WidgetTester t, String label) =>
      t.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(CheckboxListTile),
        ),
      );
  Future<void> check(WidgetTester t, String label, bool value) async {
    checkbox(t, label).onChanged!(value);
    await t.pump();
  }

  Future<void> close(WidgetTester t) async {
    if (pins.release != null && !pins.release!.isCompleted) {
      pins.release!.complete();
    }
    registry.authorityWillChangeCallback = null;
    registry.authorityChangedCallback = null;
    await t.pumpWidget(const SizedBox());
    await settle(t);
    FilePicker.platform = oldPicker;
    MainPageBridge.reloadProfilePolicy = null;
    LocalEngineStorage.instance.resetProfileScope();
    ProfileBootstrap.debugInstallRegistry(null);
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileAvatarPolicy.debugSetUserImagesSupported(null);
    await t.runAsync(() async {
      await registry.close();
      await root.delete(recursive: true);
    });
    await t.binding.setSurfaceSize(null);
    t.view.resetDevicePixelRatio();
  }
}

Future<void> editProfileCase(
  WidgetTester t,
  Future<void> Function(EditProfileFixture) body,
) async {
  final f = EditProfileFixture();
  await t.runAsync(f.open);
  try {
    await body(f);
  } finally {
    await f.close(t);
  }
}

Uint8List editProfilePng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGM4ESDyHx9mGBkKAIMRisEv0fosAAAAAElFTkSuQmCC',
);
