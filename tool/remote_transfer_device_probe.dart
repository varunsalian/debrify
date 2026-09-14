// Local validation entry point. Install only on a disposable device/emulator.
// Uses isolated scratch profiles; never opens the user's production registry.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_channel_file.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_reliable_transfer.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/utils/app_storage.dart';

final status = ValueNotifier('Starting isolated Remote transfer validation…');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, value, _) => Text(value, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
  unawaited(_run());
}

void record(String event, Map<String, Object?> fields) {
  final line = jsonEncode({'event': event, ...fields});
  // Structural diagnostics only. This fixture contains no user data.
  // ignore: avoid_print
  print('REMOTE_DEVICE_PROBE $line');
  status.value = line;
}

Future<void> _run() async {
  final root = await Directory.systemTemp.createTemp('debrify-device-probe-');
  RemoteReliableTransfer? sender;
  RemoteReliableTransfer? receiver;
  ProfileRegistry? registry;
  final state = RemoteControlState()..debugReliablePort = 0;
  try {
    await Future<void>.delayed(const Duration(seconds: 2));
    final baseline = ProcessInfo.currentRss;
    final key = List<int>.generate(32, (i) => i);
    final source = File('${root.path}/64m.bin');
    final random = Random(42);
    final block = Uint8List.fromList(
      List<int>.generate(64 * 1024, (_) => random.nextInt(256)),
    );
    final sink = source.openWrite();
    for (var i = 0; i < 1024; i++) {
      sink.add(block);
      if (i % 16 == 0) await sink.flush();
    }
    await sink.close();
    var imports = 0;
    receiver = RemoteReliableTransfer(
      directory: Directory('${root.path}/receiver'),
      receiveKey: (_, _) async => key,
      onReceive: (transfer) async {
        if (await transfer.file.length() != 64 * 1024 * 1024)
          throw StateError('Truncated file');
        imports++;
      },
    );
    sender = RemoteReliableTransfer(
      directory: Directory('${root.path}/sender'),
      receiveKey: (_, _) async => key,
      onReceive: (_) async {},
    );
    await receiver.start(port: 0);
    await sender.start(port: 0);
    final timer = Stopwatch()..start();
    await sender.send(
      host: '127.0.0.1',
      port: receiver.port,
      sessionId: 'probe',
      key: key,
      file: source,
      metadata: {'kind': 'binary-benchmark'},
    );
    if (imports != 1) throw StateError('Duplicate import');
    record('binary_pass', {
      'bytes': 64 * 1024 * 1024,
      'elapsedMs': timer.elapsedMilliseconds,
      'baselineRss': baseline,
      'currentRss': ProcessInfo.currentRss,
      'maxRss': ProcessInfo.maxRss,
    });

    final documents = await Directory('${root.path}/docs').create();
    final support = await Directory('${root.path}/support').create();
    final cache = await Directory('${root.path}/cache').create();
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(path: '${support.path}/profiles.db');
    final admin = await registry.createProfile(
      name: 'Probe Admin',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    final scope = ProfileScope(
      profileId: admin.id,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    ProfileRemoteLease.instance.authorize(admin, scope);
    final session = RemoteSession(
      sid: Uint8List.fromList(List<int>.filled(16, 42)),
      role: RemoteSessionRole.receiver,
      keys: SessionKeys(c2s: key, s2c: key, conf: key, sas: key),
      peerStaticKey: const [8],
      peerFingerprint: 'probe-sender',
      peerName: 'Probe',
      sasCode: '123456',
      establishedAt: DateTime.now(),
    )..authorized = true;
    final manager = RemoteSessionManager(
      loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
      deviceName: () => 'Probe TV',
    );
    manager.sessions[session.sidB64] = session;
    state
      ..debugInstallSessionManager(manager)
      ..debugInstallOutboundSession(session, ip: '127.0.0.1')
      ..debugRememberPeer(session.peerFingerprint);
    final port = await state.debugStartReliableReceiver();
    final db = await DebrifyTvDatabase.instance.database;
    await db.insert('tv_channels', {
      'channel_id': 'source',
      'name': 'Probe channel',
      'avoid_nsfw': 1,
      'channel_number': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('tv_channel_keywords', {
      'channel_id': 'source',
      'position': 0,
      'keyword': 'current',
    });
    const hashes = 20000;
    for (var start = 0; start < hashes; start += 500) {
      final batch = db.batch();
      for (var i = start; i < start + 500; i++) {
        batch.insert('tv_cached_torrents', {
          'channel_id': 'source',
          'infohash': i.toRadixString(16).padLeft(40, '0'),
          'name': 'Probe title $i',
          'size_bytes': i + 1,
          'created_unix': 1,
          'seeders': 5,
          'leechers': 0,
          'completed': 1,
          'scraped_date': 1,
          'keywords_json': '["previous"]',
          'sources_json': '["probe"]',
          'added_at': i,
        });
      }
      await batch.commit(noResult: true);
    }
    final channel = File('${root.path}/channel.gz');
    timer.reset();
    await RemoteChannelFile.export('source', channel);
    final preparationMs = timer.elapsedMilliseconds;
    await db.delete('tv_cached_torrents');
    timer.reset();
    final result = await sender.send(
      host: '127.0.0.1',
      port: port,
      sessionId: session.sidB64,
      key: key,
      file: channel,
      metadata: {'format': 'channel-records-v1', 'requestId': 'device-probe'},
    );
    if (jsonDecode(result!['data'] as String)['ok'] != true)
      throw StateError('Import refused');
    final actual = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM tv_cached_torrents',
    )).single['n'];
    if (actual != hashes) throw StateError('Hash pool incomplete');
    record('channel_pass', {
      'hashes': actual,
      'preparationMs': preparationMs,
      'transferAndImportMs': timer.elapsedMilliseconds,
      'wireBytes': await channel.length(),
      'currentRss': ProcessInfo.currentRss,
      'maxRss': ProcessInfo.maxRss,
    });
    record('passed', {'maxRss': ProcessInfo.maxRss});
  } catch (error, stack) {
    record('failed', {
      'errorType': error.runtimeType.toString(),
      'message': error.toString(),
    });
    // This entrypoint operates only on synthetic fixtures.
    // ignore: avoid_print
    print(stack);
  } finally {
    await sender?.close();
    await receiver?.close();
    await state.debugResetForTesting();
    await DebrifyTvDatabase.instance.closeScope();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    AppStorage.debugReset();
    await registry?.close();
    await root.delete(recursive: true);
  }
}
