import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_chunked_send.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Origin pin for the Debrify-channel chunked transfer machinery inside
/// `RemoteCommandRouter` (`_handleDebrifyChannelStart`, `_armChunkTimeout`,
/// `_handleDebrifyChannelChunk`, `_completeEncryptedBlob`, `_ChunkBuffer`)
/// and the stale-remote drop notice (`_noteUnauthenticatedDrop`,
/// `_StaleRemoteSource`).
///
/// Everything is driven through the router's own public entry points — no
/// source-text greps, no re-implementation of the moved bodies.
void main() {
  final router = RemoteCommandRouter();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ── v1 (plain) transport: buffering, stall deadline, envelope rejection ──
  //
  // Plain transfers keep the original single long deadline and report the
  // stall on-screen, because a silent drop reads as success to the sender.
  group('plain (v1) chunk transport', () {
    late GlobalKey<ScaffoldMessengerState> messengerKey;

    Future<void> pumpHost(WidgetTester tester) async {
      messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      router.setScaffoldMessengerKey(messengerKey);
    }

    setUp(() {
      ProfileRuntime.debugReset();
      router.clearProfileSessionState();
    });

    tearDown(() {
      router.clearProfileSessionState();
      ProfileRuntime.debugReset();
    });

    testWidgets('a stalled transfer reports the stall on the receiver', (
      tester,
    ) async {
      await pumpHost(tester);
      const context = RemoteCommandContext(
        encrypted: false,
        authorized: false,
        sourceIp: '192.168.1.77',
      );
      final chunks = encodePayloadChunks('x' * 4000);
      expect(chunks.length, greaterThan(2));

      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.debrifyChannelStart,
        chunkStartBody(
          transferId: 'stalled-transfer',
          command: ConfigCommand.searchEngines,
          label: 'My Channel',
          totalChunks: chunks.length,
        ),
        context,
      );

      // One chunk lands, the rest never do.
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.debrifyChannelChunk,
        chunkPieceBody(
          transferId: 'stalled-transfer',
          index: 0,
          data: chunks.first,
        ),
        context,
      );

      await tester.pump(kChunkTransferTimeout - const Duration(seconds: 1));
      expect(find.text('Transfer timed out: My Channel'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Transfer timed out: My Channel'), findsOneWidget);
    });

    testWidgets('an unparseable start envelope is reported, not thrown', (
      tester,
    ) async {
      await pumpHost(tester);
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.debrifyChannelStart,
        '{"transferId":"bad"}',
        const RemoteCommandContext(
          encrypted: false,
          authorized: false,
          sourceIp: '192.168.1.78',
        ),
      );
      // The rejection notice is banked by the import batcher (the start packet
      // opened the batch window) and raised once the idle window closes.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(find.text('Failed to receive transfer'), findsOneWidget);
    });

    testWidgets('a transfer naming a transport command is refused outright', (
      tester,
    ) async {
      await pumpHost(tester);
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.debrifyChannelStart,
        chunkStartBody(
          transferId: 'recursive-transfer',
          command: ConfigCommand.debrifyChannelStart,
          label: 'Recursive',
          totalChunks: 2,
        ),
        const RemoteCommandContext(
          encrypted: false,
          authorized: false,
          sourceIp: '192.168.1.79',
        ),
      );
      await tester.pump(kChunkTransferTimeout + const Duration(seconds: 2));
      await tester.pump();

      // Refused silently: no buffer was created, so no stall deadline and no
      // "failed to receive" notice either.
      expect(find.text('Failed to receive transfer'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  // ── v2 (sealed) transport: reassembly, decryption, replay ────────────────
  group('encrypted (v2) chunk transport', () {
    late Directory temporaryDirectory;
    late ProfileRegistry registry;
    late RemoteSession session;
    late RemoteSessionManager manager;
    late RemoteCommandContext peer;

    // Long enough that the sealed ciphertext spans several chunk packets.
    final secret = 'real-debrid-secret-${'p' * 2000}';

    RemoteSession buildSession() {
      final sid = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      final keys = SessionKeys(
        c2s: List<int>.generate(32, (i) => i),
        s2c: List<int>.generate(32, (i) => 255 - i),
        conf: List<int>.filled(32, 7),
        sas: List<int>.filled(32, 9),
      );
      return RemoteSession(
        sid: sid,
        role: RemoteSessionRole.receiver,
        keys: keys,
        peerStaticKey: List<int>.filled(32, 3),
        peerFingerprint: 'peer-one',
        peerName: 'Phone',
        sasCode: '123456',
        establishedAt: DateTime.now(),
      )..authorized = true;
    }

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'remote-chunk-transfer-pin-',
      );
      registry = await ProfileRegistry.open(
        path: p.join(temporaryDirectory.path, 'profiles.db'),
      );
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
        policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
      );
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.debugReset();
      final scope = ProfileScope(
        profileId: admin.id,
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      ProfileRemoteLease.instance.authorize(
        (await registry.getProfile(admin.id))!,
        scope,
      );

      session = buildSession();
      manager = RemoteSessionManager(
        loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
        deviceName: () => 'TV',
      );
      manager.sessions[session.sidB64] = session;
      RemoteControlState().debugInstallSessionManager(manager);

      peer = RemoteCommandContext(
        encrypted: true,
        authorized: true,
        sidB64: session.sidB64,
        peerFingerprint: 'peer-one',
        peerName: 'Phone',
      );
      router.clearProfileSessionState();
    });

    tearDown(() async {
      router.clearProfileSessionState();
      ProfileRemoteLease.instance.revoke();
      ProfileRuntime.debugReset();
      ProfileBootstrap.debugInstallRegistry(null);
      await registry.close();
      await temporaryDirectory.delete(recursive: true);
    });

    /// Seal [payload] for this session exactly as the sender does and slice it.
    Future<List<String>> sealedChunks({
      required String transferId,
      required String kind,
      required int n,
      String? payload,
    }) async {
      final ctB64 = await RemoteSessionCrypto.sealBlob(
        key: session.recvKey,
        sid: session.sid,
        n: n,
        transferId: transferId,
        kind: kind,
        payload: payload ?? secret,
      );
      return encodePayloadChunks(ctB64);
    }

    Future<void> start({
      required String transferId,
      required String kind,
      required int totalChunks,
      required int n,
      String label = 'Sealed transfer',
    }) => router.debugDispatchAndWait(
      RemoteAction.config,
      ConfigCommand.debrifyChannelStart,
      chunkStartBody(
        transferId: transferId,
        command: kind,
        label: label,
        totalChunks: totalChunks,
        encSidB64: session.sidB64,
        encN: n,
      ),
      peer,
    );

    Future<void> piece(String transferId, int index, String data) =>
        router.debugDispatchAndWait(
          RemoteAction.config,
          ConfigCommand.debrifyChannelChunk,
          chunkPieceBody(transferId: transferId, index: index, data: data),
          peer,
        );

    test('in-order chunks decrypt and replay the payload', () async {
      const transferId = 'sealed-in-order';
      final chunks = await sealedChunks(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        n: 1,
      );
      await start(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        totalChunks: chunks.length,
        n: 1,
      );
      for (var i = 0; i < chunks.length; i++) {
        await piece(transferId, i, chunks[i]);
      }

      expect(router.debugProfileTransferKeys, contains('realDebridApiKey'));
      expect(router.debugProfileTransferValue('realDebridApiKey'), secret);
    });

    test('out-of-order and duplicate chunks still reassemble once', () async {
      const transferId = 'sealed-out-of-order';
      final chunks = await sealedChunks(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        n: 2,
      );
      expect(
        chunks.length,
        greaterThanOrEqualTo(2),
        reason: 'the pin needs a multi-chunk payload to reorder',
      );
      await start(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        totalChunks: chunks.length,
        n: 2,
      );

      // Last piece first, then a duplicate of it (a duplicate UDP packet must
      // not be counted twice), then the rest in reverse.
      final last = chunks.length - 1;
      await piece(transferId, last, chunks[last]);
      await piece(transferId, last, chunks[last]);
      expect(
        router.debugProfileTransferKeys,
        isNot(contains('realDebridApiKey')),
        reason: 'a duplicate must not fake a complete transfer',
      );
      for (var i = last - 1; i >= 0; i--) {
        await piece(transferId, i, chunks[i]);
      }

      expect(router.debugProfileTransferValue('realDebridApiKey'), secret);
    });

    test(
      'a repeated start packet does not wipe chunks already filed',
      () async {
        const transferId = 'sealed-repeat-start';
        final chunks = await sealedChunks(
          transferId: transferId,
          kind: ConfigCommand.realDebrid,
          n: 3,
        );
        expect(chunks.length, greaterThanOrEqualTo(2));
        await start(
          transferId: transferId,
          kind: ConfigCommand.realDebrid,
          totalChunks: chunks.length,
          n: 3,
        );
        await piece(transferId, 0, chunks.first);

        // The sender fires its start packet twice; the second one must be a
        // no-op for a transfer that is already receiving.
        await start(
          transferId: transferId,
          kind: ConfigCommand.realDebrid,
          totalChunks: chunks.length,
          n: 3,
        );
        for (var i = 1; i < chunks.length; i++) {
          await piece(transferId, i, chunks[i]);
        }

        expect(router.debugProfileTransferValue('realDebridApiKey'), secret);
      },
    );

    test('an out-of-range chunk index is dropped, not fatal', () async {
      const transferId = 'sealed-bad-index';
      final chunks = await sealedChunks(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        n: 4,
      );
      await start(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        totalChunks: chunks.length,
        n: 4,
      );
      await piece(transferId, chunks.length + 5, chunks.first);
      await piece(transferId, -1, chunks.first);
      for (var i = 0; i < chunks.length; i++) {
        await piece(transferId, i, chunks[i]);
      }

      expect(router.debugProfileTransferValue('realDebridApiKey'), secret);
    });

    test('a chunk for an unknown transfer is ignored', () async {
      await piece('no-such-transfer', 0, base64.encode(utf8.encode('junk')));
      expect(router.debugProfileTransferKeys, isEmpty);
    });

    test('a blob sealed under a different counter never applies', () async {
      const transferId = 'sealed-wrong-n';
      final chunks = await sealedChunks(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        n: 9,
      );
      // The start packet claims counter 10 while the ciphertext was bound to
      // 9: the AEAD must refuse and nothing may be staged.
      await start(
        transferId: transferId,
        kind: ConfigCommand.realDebrid,
        totalChunks: chunks.length,
        n: 10,
      );
      for (var i = 0; i < chunks.length; i++) {
        await piece(transferId, i, chunks[i]);
      }

      expect(router.debugProfileTransferKeys, isEmpty);
    });
  });

  // ── stale remote sources ─────────────────────────────────────────────────
  group('stale remote source notice', () {
    late Directory temporaryDirectory;
    late ProfileRegistry registry;

    setUp(() async {
      ProfileRuntime.debugReset();
      router.debugResetStaleRemoteNotices();
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'remote-chunk-transfer-stale-pin-',
      );
      registry = await ProfileRegistry.open(
        path: p.join(temporaryDirectory.path, 'profiles.db'),
      );
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
        policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: true,
      );
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
      );
    });

    tearDown(() async {
      await registry.close();
      ProfileBootstrap.debugInstallRegistry(null);
      ProfileRuntime.debugReset();
      router.debugResetStaleRemoteNotices();
      await temporaryDirectory.delete(recursive: true);
    });

    Future<void> plaintextDrop(String sourceIp) => router.debugDispatchAndWait(
      RemoteAction.navigate,
      NavigateCommand.up,
      null,
      RemoteCommandContext(
        encrypted: false,
        authorized: false,
        sourceIp: sourceIp,
      ),
    );

    test('a burst from one source raises exactly one notice', () async {
      await plaintextDrop('10.0.0.5');
      await plaintextDrop('10.0.0.5');
      expect(router.debugStaleRemoteNoticeCount, 0);

      await plaintextDrop('10.0.0.5');
      expect(router.debugStaleRemoteNoticeCount, 1);

      for (var i = 0; i < 8; i++) {
        await plaintextDrop('10.0.0.5');
      }
      expect(
        router.debugStaleRemoteNoticeCount,
        1,
        reason: 'the cooldown must not parade a notice per keypress',
      );
    });

    test('drops are tallied per source, never pooled', () async {
      await plaintextDrop('10.0.0.5');
      await plaintextDrop('10.0.0.6');
      await plaintextDrop('10.0.0.7');
      expect(router.debugStaleRemoteNoticeCount, 0);
    });
  });
}
