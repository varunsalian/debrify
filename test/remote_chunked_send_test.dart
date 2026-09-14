import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/remote_control/remote_chunked_send.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/remote_control/udp_command_service.dart';
import 'package:debrify/services/remote_control/udp_discovery_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The framing that carries an oversized config payload to a TV.
///
/// UDP has no retransmission here, so a packet that exceeds the MTU and gets
/// fragmented (or dropped) costs the entire transfer with no error anywhere.
/// The size budget in [kChunkRawBytesPerChunk] was computed by hand; these
/// tests are what keep it honest as the envelope changes.
void main() {
  encryptedBudgetTests();
  productionRouteIntegrationTest();
  String packetFor(String data) => chunkPieceBody(
    // Worst case for the id: the real one is microseconds + a hash, so
    // pad to a length no live transfer will exceed.
    transferId: '9' * 40,
    index: 999999,
    data: data,
  );

  group('packet budget', () {
    test('a full chunk packet still fits one datagram', () {
      final payload = 'x' * (kChunkRawBytesPerChunk * 3);
      final chunks = encodePayloadChunks(payload);

      // The first chunk is a full slice — the worst case.
      final packet = packetFor(chunks.first);
      expect(utf8.encode(packet).length, lessThanOrEqualTo(kChunkMaxBytes));
    });

    test('a start packet fits one datagram', () {
      final body = chunkStartBody(
        transferId: '9' * 40,
        command: ConfigCommand.iptvFavorites,
        label: 'IPTV favorites',
        totalChunks: 99999,
      );
      expect(utf8.encode(body).length, lessThanOrEqualTo(kChunkMaxBytes));
    });

    test('multi-byte text does not overflow a packet', () {
      // base64 of N bytes is the same length whatever those bytes are, but a
      // payload of emoji reaches the byte budget in a quarter of the
      // characters — the slicing has to be by bytes, not runes.
      final payload = '🎬' * 2000;
      final chunks = encodePayloadChunks(payload);
      for (final chunk in chunks) {
        expect(
          utf8.encode(packetFor(chunk)).length,
          lessThanOrEqualTo(kChunkMaxBytes),
        );
      }
    });
  });

  group('single-packet threshold', () {
    test('accounts for the escaping the envelope adds', () {
      // A JSON array of channel records is mostly quotes, and the sender
      // embeds this string inside another JSON document — so every quote
      // costs two bytes on the wire. Fill right up to the raw budget and the
      // escaped form is well past it: measuring raw length would send this as
      // one oversized datagram that fragments and vanishes.
      final records = <Map<String, String>>[];
      var payload = '[]';
      while (true) {
        final next = [
          ...records,
          {
            'url':
                'http://panel.example:8080/live/user/pw/${records.length}.ts',
            'name': 'Channel ${records.length}',
            'playlistId': 'p1',
          },
        ];
        if (jsonEncode(next).length > kChunkDataMaxBytes) break;
        records.add(next.last);
        payload = jsonEncode(records);
      }

      expect(
        payload.length,
        lessThanOrEqualTo(kChunkDataMaxBytes),
        reason: 'raw length fits the budget',
      );
      expect(
        fitsSinglePacket(payload),
        isFalse,
        reason: 'but the escaped form does not',
      );
    });

    test('a small payload still goes direct', () {
      expect(fitsSinglePacket(jsonEncode({'access_token': 'abc123'})), isTrue);
    });

    test('anything rejected by the threshold survives chunking', () {
      final payload = jsonEncode([
        for (var i = 0; i < 8; i++)
          {'url': 'http://panel.example:8080/live/user/pw/$i.ts'},
      ]);
      if (!fitsSinglePacket(payload)) {
        expect(decodePayloadChunks(encodePayloadChunks(payload)), payload);
      }
    });
  });

  group('profile graph size policy', () {
    test('compacts above either soft transport threshold', () {
      expect(
        profileGraphTransportNeedsCompaction(
          wireBytes: kMaxProfileGraphWireBytes,
          expandedBytes: kProfileGraphCompactionThresholdBytes,
        ),
        isFalse,
      );
      expect(
        profileGraphTransportNeedsCompaction(
          wireBytes: kMaxProfileGraphWireBytes + 1,
          expandedBytes: kProfileGraphCompactionThresholdBytes,
        ),
        isTrue,
      );
      expect(
        profileGraphTransportNeedsCompaction(
          wireBytes: kMaxProfileGraphWireBytes,
          expandedBytes: kProfileGraphCompactionThresholdBytes + 1,
        ),
        isTrue,
      );
      expect(
        kMaxProfileGraphExpandedBytes,
        greaterThan(kProfileGraphCompactionThresholdBytes),
      );
    });
  });

  group('profile graph result', () {
    test('acknowledgement failure stays a delivery failure', () async {
      final router = RemoteCommandRouter();
      expect(
        await router.debugRunBestEffortProfileGraphResult(
          () async => throw StateError('socket authorization changed'),
        ),
        isFalse,
      );
      expect(
        await router.debugRunBestEffortProfileGraphResult(() async => true),
        isTrue,
      );
    });

    test('outcome body round-trips and rejects malformed input', () {
      final body = profileGraphResultBody(
        requestId: 'request-123',
        ok: false,
        message: 'Open an Admin profile on the TV, then resend',
      );
      final parsed = parseProfileGraphResultBody(body);
      expect(parsed, isNotNull);
      expect(parsed!.requestId, 'request-123');
      expect(parsed.ok, isFalse);
      expect(parsed.message, contains('Admin profile'));
      expect(
        profileGraphResultMatchesRequest(
          requestId: 'request-123',
          resultRequestId: parsed.requestId,
        ),
        isTrue,
      );
      expect(
        profileGraphResultMatchesRequest(
          requestId: 'new-attempt',
          resultRequestId: parsed.requestId,
        ),
        isFalse,
        reason: 'a late result from the previous attempt must be ignored',
      );
      expect(
        profileGraphResultMatchesRequest(
          requestId: 'request-123',
          resultRequestId: null,
        ),
        isFalse,
        reason: 'an uncorrelated legacy result must not complete this send',
      );

      expect(parseProfileGraphResultBody('not json'), isNull);
      expect(parseProfileGraphResultBody('{"ok":"yes","message":1}'), isNull);
      // A hostile peer must not be able to pump an unbounded string into a
      // sender-side toast.
      expect(
        parseProfileGraphResultBody('{"ok":true,"message":"${'x' * 600}"}'),
        isNull,
      );
    });
  });

  group('addon transfer result', () {
    test('outcome body is correlated and bounded', () {
      final parsed = parseAddonTransferResultBody(
        addonTransferResultBody(requestId: 'addon-request-1', ok: true),
      );
      expect(parsed, isNotNull);
      expect(parsed!.requestId, 'addon-request-1');
      expect(parsed.ok, isTrue);
      expect(parseAddonTransferResultBody('not json'), isNull);
      expect(
        parseAddonTransferResultBody('{"requestId":"${'x' * 129}","ok":true}'),
        isNull,
      );
      expect(
        parseAddonTransferResultBody(
          '{"requestId":"addon-request-1","ok":"yes"}',
        ),
        isNull,
      );
    });

    test('discovery capability starts at protocol v3', () {
      expect(
        DiscoveredDevice(
          deviceName: 'TV',
          ip: 'local',
          protoVersion: 2,
        ).supportsAddonTransferResult,
        isFalse,
      );
      expect(
        DiscoveredDevice(
          deviceName: 'TV',
          ip: 'local',
          protoVersion: 3,
        ).supportsAddonTransferResult,
        isTrue,
      );
    });
  });

  group('generic remote transfer result', () {
    test('request, item, result, and channel envelopes round-trip', () {
      const requestId = 'remote-request-1';
      final request = parseRemoteTransferRequestBody(
        remoteTransferRequestBody(
          requestId,
          expectedCommands: const [
            ConfigCommand.realDebrid,
            RemoteAction.addon,
            RemoteAction.addon,
          ],
        ),
      );
      expect(request, isNotNull);
      expect(request!.requestId, requestId);
      expect(request.expected, {
        ConfigCommand.realDebrid: 1,
        RemoteAction.addon: 2,
      });

      final item = parseRemoteTransferItemBody(
        remoteTransferItemBody(requestId: requestId, payload: 'secret'),
      );
      expect(item, isNotNull);
      expect(item!.requestId, requestId);
      expect(item.payload, 'secret');
      expect(parseRemoteTransferItemBody('secret'), isNull);
      expect(
        parseRemoteTransferItemBody(
          remoteTransferItemBody(requestId: 'x' * 129, payload: 'secret'),
        ),
        isNull,
      );

      final result = parseRemoteTransferResultBody(
        remoteTransferResultBody(
          requestId: requestId,
          ok: true,
          message: 'Applied on TV',
        ),
      );
      expect(result, isNotNull);
      expect(result!.requestId, requestId);
      expect(result.ok, isTrue);
      expect(result.message, 'Applied on TV');

      const uri = 'debrify://channel-payload';
      final channel = parseRemoteChannelTransferBody(
        remoteChannelTransferBody(requestId: requestId, uri: uri),
      );
      expect(channel, isNotNull);
      expect(channel!.requestId, requestId);
      expect(channel.uri, uri);

      final chunkStart = chunkStartBody(
        transferId: 'transfer-1',
        command: ConfigCommand.debrifyChannel,
        label: 'Channel',
        totalChunks: 2,
        resultRequestId: requestId,
      );
      expect(parseChunkResultRequestId(chunkStart), requestId);
      expect(parseChunkResultCommand(chunkStart), ConfigCommand.debrifyChannel);
    });

    test('malformed and oversized outcome envelopes are rejected', () {
      expect(parseRemoteTransferRequestBody(null), isNull);
      expect(parseRemoteTransferRequestBody('not json'), isNull);
      expect(
        parseRemoteTransferRequestBody(
          '{"version":1,"requestId":"${'x' * 129}"}',
        ),
        isNull,
      );
      expect(
        parseRemoteTransferRequestBody(
          '{"version":1,"requestId":"ok","expected":{"addon":0}}',
        ),
        isNull,
      );
      expect(
        parseRemoteTransferRequestBody(
          '{"version":1,"requestId":"ok","expected":{"addon":201}}',
        ),
        isNull,
      );
      expect(parseRemoteTransferResultBody('not json'), isNull);
      expect(
        parseRemoteTransferResultBody(
          '{"requestId":"ok","ok":true,"message":"${'x' * 501}"}',
        ),
        isNull,
      );
      expect(parseRemoteChannelTransferBody('{"version":1}'), isNull);
      expect(parseChunkResultRequestId('{"resultRequestId":""}'), isNull);
      expect(parseChunkResultCommand('{"kind":""}'), isNull);
      expect(
        parseRemoteChannelTransferBody(
          remoteChannelTransferBody(requestId: 'ok', uri: 'https://wrong'),
        ),
        isNull,
      );
    });

    test('discovery capability starts at protocol v4', () {
      expect(
        DiscoveredDevice(
          deviceName: 'TV',
          ip: 'local',
          protoVersion: 3,
        ).supportsRemoteTransferResult,
        isFalse,
      );
      expect(
        DiscoveredDevice(
          deviceName: 'TV',
          ip: 'local',
          protoVersion: 4,
        ).supportsRemoteTransferResult,
        isTrue,
      );
    });

    test('complete profile graph capability starts at protocol v5', () {
      expect(
        DiscoveredDevice(
          deviceName: 'TV',
          ip: 'local',
          protoVersion: 4,
        ).supportsComprehensiveProfileGraph,
        isFalse,
      );
      expect(
        DiscoveredDevice(
          deviceName: 'TV',
          ip: 'local',
          protoVersion: 5,
        ).supportsComprehensiveProfileGraph,
        isTrue,
      );
      expect(
        kProtoVersion,
        greaterThanOrEqualTo(kComprehensiveProfileGraphProtocolVersion),
      );
    });

    test(
      'manual-IP capability stays probeable until handshake identifies it',
      () {
        final manual = DiscoveredDevice(
          deviceName: 'VPN TV',
          ip: '100.64.0.2',
          protocolVersionKnown: false,
        );
        expect(manual.supportsComprehensiveProfileGraph, isFalse);
        expect(manual.maySupportComprehensiveProfileGraph, isTrue);

        final current = manual.withProtocolVersion(5);
        expect(current.protocolVersionKnown, isTrue);
        expect(current.maySupportComprehensiveProfileGraph, isTrue);
        expect(
          DiscoveredDevice.fromJson(current.toJson()).protocolVersionKnown,
          isTrue,
        );

        final old = manual.withProtocolVersion(4);
        expect(old.protocolVersionKnown, isTrue);
        expect(old.maySupportComprehensiveProfileGraph, isFalse);
      },
    );
  });

  group('round trip', () {
    test('reassembles exactly what was sent', () {
      final payload = jsonEncode([
        for (var i = 0; i < 400; i++)
          {
            'url': 'http://panel.example:8080/live/user/pw/$i.ts',
            'name': 'Channel $i',
            'group': 'Entertainment',
            'playlistId': 'p1',
          },
      ]);

      final chunks = encodePayloadChunks(payload);

      expect(chunks.length, greaterThan(1), reason: 'payload should chunk');
      expect(decodePayloadChunks(chunks), payload);
    });

    test('survives a character straddling a slice boundary', () {
      // Decoding each slice on its own would split this emoji's bytes across
      // two utf8.decode calls and corrupt it.
      final payload = '${'a' * (kChunkRawBytesPerChunk - 2)}🎬${'b' * 50}';
      expect(decodePayloadChunks(encodePayloadChunks(payload)), payload);
    });

    test('a payload just over the single-packet budget chunks cleanly', () {
      final payload = 'y' * (kChunkDataMaxBytes + 1);
      final chunks = encodePayloadChunks(payload);
      expect(decodePayloadChunks(chunks), payload);
    });
  });

  group('start packet', () {
    test('names the command so the receiver can replay it', () {
      final decoded =
          jsonDecode(
                chunkStartBody(
                  transferId: 't1',
                  command: ConfigCommand.iptvLists,
                  label: 'IPTV lists',
                  totalChunks: 7,
                ),
              )
              as Map<String, dynamic>;

      expect(decoded['kind'], ConfigCommand.iptvLists);
      expect(decoded['totalChunks'], 7);
      // Receivers built before `kind` existed read this key and would throw
      // on its absence.
      expect(decoded['channelName'], 'IPTV lists');
    });
  });
}

void productionRouteIntegrationTest() {
  group('production encrypted chunk route', () {
    late Directory temporaryDirectory;
    late ProfileRegistry registry;
    final state = RemoteControlState()..debugReliablePort = 0;
    final router = RemoteCommandRouter();

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'remote-chunk-route-test-',
      );
      registry = await ProfileRegistry.open(
        path: p.join(temporaryDirectory.path, 'profiles.db'),
      );
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.debugReset();
      final scope = ProfileScope(
        profileId: admin.id,
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      ProfileRemoteLease.instance.authorize(admin, scope);
      router.clearProfileSessionState();
      await state.debugResetForTesting();
    });

    tearDown(() async {
      await state.debugResetForTesting();
      router.clearProfileSessionState();
      ProfileRemoteLease.instance.revoke();
      ProfileRuntime.debugReset();
      ProfileBootstrap.debugInstallRegistry(null);
      await registry.close();
      await temporaryDirectory.delete(recursive: true);
    });

    test(
      'reorder, duplicate, and replay preserve exact sealed source',
      () async {
        final sid = Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]);
        const keys = SessionKeys(
          c2s: <int>[
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
          ],
          s2c: <int>[
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
            2,
          ],
          conf: <int>[
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
            3,
          ],
          sas: <int>[
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
            4,
          ],
        );
        final sender = RemoteSession(
          peerProtocolVersion: 5,
          sid: sid,
          role: RemoteSessionRole.sender,
          keys: keys,
          peerStaticKey: const <int>[9],
          peerFingerprint: 'receiver-fingerprint',
          peerName: 'Receiver',
          sasCode: '123456',
          establishedAt: DateTime.utc(2026, 8, 13),
        )..authorized = true;
        final receiver = RemoteSession(
          peerProtocolVersion: 5,
          sid: sid,
          role: RemoteSessionRole.receiver,
          keys: keys,
          peerStaticKey: const <int>[8],
          peerFingerprint: 'sender-fingerprint',
          peerName: 'Sender',
          sasCode: '123456',
          establishedAt: DateTime.utc(2026, 8, 13),
        )..authorized = true;
        final manager = RemoteSessionManager(
          loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
          deviceName: () => 'Receiver',
        );
        manager.sessions[receiver.sidB64] = receiver;
        state
          ..debugInstallSessionManager(manager)
          ..debugInstallOutboundSession(sender, ip: 'receiver')
          ..debugInstallOutboundSession(receiver, ip: 'sender')
          ..debugRememberPeer(receiver.peerFingerprint);

        final rememberedChunkContext = state.debugAuthenticatedChunkContext(
          RemoteCommand(
            action: RemoteAction.config,
            command: ConfigCommand.debrifyChannelStart,
            data: '{}',
          ),
          'sender',
        );
        expect(rememberedChunkContext, isNotNull);
        expect(rememberedChunkContext!.remembered, isTrue);

        final wire = <Map<String, dynamic>>[];
        state.debugPlainSender = (command, _, _) async {
          wire.add(Map<String, dynamic>.from(command));
          return true;
        };
        final payload = 'PRIVATE_SOURCE_${'x' * 6000}';
        expect(
          await sendConfigPayloadToDevice(
            state,
            ConfigCommand.realDebrid,
            'receiver',
            payload,
            label: 'Real-Debrid',
          ),
          isTrue,
        );
        expect(wire.length, greaterThan(2));
        expect(jsonEncode(wire), isNot(contains('PRIVATE_SOURCE')));

        final start = wire.first;
        final chunks = wire.skip(1).toList().reversed.toList();
        Future<void> deliver(Map<String, dynamic> packet) =>
            state.debugReceiveCommandAndWait(
              RemoteCommand.fromJson(packet),
              'sender',
            );
        await deliver(start);
        await deliver(chunks.first);
        await deliver(chunks.first);
        for (final packet in chunks.skip(1)) {
          await deliver(packet);
        }
        expect(router.debugProfileTransferValue('realDebridApiKey'), payload);

        // Replaying the same sealed blob/counter is authenticated but rejected.
        await deliver(start);
        for (final packet in chunks) {
          await deliver(packet);
        }
        expect(router.debugProfileTransferValue('realDebridApiKey'), payload);
      },
    );
  });
}

/// v2 additions: sealed-blob transfers and the encrypted single-packet
/// threshold. These pin the arithmetic in [fitsSinglePacketEncrypted] against
/// the REAL sealed size — if the envelope grows, this fails before a user's
/// transfer silently fragments.
void encryptedBudgetTests() {
  group('encrypted budget', () {
    test('start packet with enc fields still fits one datagram', () {
      final body = chunkStartBody(
        transferId: '9' * 40,
        command: ConfigCommand.iptvPlaylists,
        label: 'IPTV providers',
        totalChunks: 99999,
        encSidB64: 'AAAAAAAAAAA=', // 8 bytes base64
        encN: 1 << 52,
      );
      expect(utf8.encode(body).length, lessThanOrEqualTo(kChunkMaxBytes));
      // And the legacy field is still there for old receivers.
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      expect(decoded['channelName'], 'IPTV providers');
      expect(decoded['enc'], 1);
    });

    test('worst-case sealed ecmd at the threshold fits one datagram', () async {
      // Find the largest payload the threshold accepts.
      var lo = 0, hi = kChunkDataMaxBytes;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        if (fitsSinglePacketEncrypted('x' * mid)) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      expect(lo, greaterThan(700)); // sanity: threshold isn't degenerate

      // Seal a REAL worst-case command envelope around it and measure the
      // full ecmd datagram.
      final payload = 'x' * lo;
      final commandJson = jsonEncode({
        'type': 'command',
        'action': 'config',
        'command': ConfigCommand.indexerManagers,
        'data': payload,
      });
      final ct = await RemoteSessionCrypto.sealEcmd(
        key: List<int>.filled(32, 7),
        sid: List<int>.filled(8, 1),
        n: 1 << 52, // worst-case digit count for a realistic counter
        commandJson: commandJson,
      );
      final envelope = jsonEncode({
        'type': 'ecmd',
        'sid': 'AAAAAAAAAAA=',
        'n': 1 << 52,
        'ct': ct,
      });
      expect(utf8.encode(envelope).length, lessThanOrEqualTo(kChunkMaxBytes));
    });

    test('payload over the encrypted threshold is under the plaintext one', () {
      // The encrypted path must kick in earlier than the plaintext path —
      // if these ever cross, sealed sends fragment.
      var lo = 0, hi = kChunkDataMaxBytes;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        if (fitsSinglePacketEncrypted('x' * mid)) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      expect(fitsSinglePacket('x' * lo), isTrue);
      expect(lo, lessThan(kChunkDataMaxBytes));
    });
  });

  group('gap repair', () {
    test('need body round-trips and caps the index list', () {
      final parsed = parseChunkNeedBody(
        chunkNeedBody(transferId: 't1', missing: [0, 7, 42]),
      );
      expect(parsed, isNotNull);
      expect(parsed!.transferId, 't1');
      expect(parsed.missing, [0, 7, 42]);

      // Oversized request lists are truncated at build AND parse time, so
      // neither end trusts the other about the cap.
      final huge = List<int>.generate(kChunkNeedMaxIndices * 2, (i) => i);
      final capped = parseChunkNeedBody(
        chunkNeedBody(transferId: 't2', missing: huge),
      );
      expect(capped!.missing.length, kChunkNeedMaxIndices);
    });

    test('a full need packet still fits one datagram', () {
      // Worst realistic case: the cap's worth of five-digit indices (a 16MB
      // transfer tops out under 19k chunks).
      final missing = List<int>.generate(
        kChunkNeedMaxIndices,
        (i) => 18000 - i,
      );
      final body = chunkNeedBody(transferId: 'x' * 40, missing: missing);
      // The need rides an ecmd envelope, so budget like the encrypted path.
      expect(fitsSinglePacketEncrypted(body), isTrue);
    });

    test('malformed need requests are rejected, never thrown', () {
      expect(parseChunkNeedBody('not json'), isNull);
      expect(parseChunkNeedBody('{"transferId":"t"}'), isNull);
      expect(parseChunkNeedBody('{"transferId":"t","need":[]}'), isNull);
      expect(parseChunkNeedBody('{"transferId":"t","need":[-1]}'), isNull);
      expect(parseChunkNeedBody('{"transferId":"t","need":["a"]}'), isNull);
      expect(parseChunkNeedBody('{"transferId":"","need":[1]}'), isNull);
    });
  });
}
