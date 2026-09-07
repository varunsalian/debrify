import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'remote_chunked_send.dart';
import 'remote_constants.dart';
import 'remote_control_state.dart';
import 'remote_session.dart';
import 'remote_transfer_diagnostics.dart';
import 'udp_command_service.dart';

/// Ceiling on a reassembled remote payload. Shared with the router's staged
/// profile buffer, which measures the same wire budget.
const int kMaxRemoteTransferPayloadBytes = 16 * 1024 * 1024;

/// Reports a transfer's real outcome back to the sender — delivery is not
/// application, and the phone's "sent" toast is a lie without it.
typedef RemoteTransferResultReporter =
    Future<bool> Function(
      RemoteCommandContext context, {
      required String? requestId,
      required bool ok,
      required String message,
    });

/// Receiving half of the Debrify-channel chunked transfer protocol.
///
/// A payload too large for one datagram arrives as a start packet naming the
/// config command it belongs to plus N chunk packets; this unit buffers the
/// pieces, runs the stall/gap-repair deadline, decrypts a v2 sealed blob and
/// replays the reassembled payload through the router's normal dispatch.
/// Everything it needs from the router arrives through the callbacks below —
/// it never reaches into the router itself.
class RemoteChunkTransferReceiver {
  RemoteChunkTransferReceiver({
    required this.showSnackBar,
    required this.dispatchCommand,
    required this.peerKeyOf,
    required this.reportProfileGraphResult,
    required this.reportRemoteTransferResult,
  });

  /// Receiver-side feedback; banked by the router's import batcher while a
  /// burst is in flight.
  final void Function(String message, {bool isError}) showSnackBar;

  /// Replays a reassembled payload through the router's command dispatch.
  final Future<void> Function(
    String action,
    String command,
    String? data,
    RemoteCommandContext context,
  )
  dispatchCommand;

  /// Identity a transfer is bound to, so a second peer cannot join it.
  final String? Function(RemoteCommandContext context) peerKeyOf;

  final RemoteTransferResultReporter reportProfileGraphResult;
  final RemoteTransferResultReporter reportRemoteTransferResult;

  // Chunk reassembly buffer for large channel transfers
  final Map<String, _ChunkBuffer> _chunkBuffers = {};

  /// Whether any transfer is still arriving. The batcher and the restart path
  /// both wait on this: a half-arrived transfer is not idle.
  bool get hasActiveTransfers => _chunkBuffers.isNotEmpty;

  int get activeTransferCount => _chunkBuffers.length;

  /// Drop every in-flight transfer (profile session teardown).
  void cancelAll() {
    for (final buffer in _chunkBuffers.values) {
      buffer.timeout?.cancel();
    }
    _chunkBuffers.clear();
  }

  /// Handle start of a chunked transfer. The payload can belong to any config
  /// command — the start packet names it via `kind`.
  void handleStart(String jsonData, RemoteCommandContext context) {
    String? diagnosticKind;
    String? diagnosticTrace;
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final transferId = data['transferId'] as String;
      final label = data['channelName'] as String;
      final totalChunks = data['totalChunks'] as int;
      final kind = (data['kind'] as String?) ?? ConfigCommand.debrifyChannel;
      diagnosticKind = kind;
      final encrypted = data['enc'] == 1;
      final sid = data['sid'] as String?;
      final resultRequestId = data['resultRequestId'] as String?;
      diagnosticTrace = RemoteTransferDiagnostics.traceToken(resultRequestId);
      final peer = peerKeyOf(context);

      if (transferId.isEmpty ||
          transferId.length > 160 ||
          label.length > 240 ||
          totalChunks < 1 ||
          totalChunks >
              kMaxRemoteTransferPayloadBytes ~/ kChunkRawBytesPerChunk + 1 ||
          peer == null ||
          encrypted != context.encrypted ||
          (resultRequestId != null &&
              (resultRequestId.isEmpty || resultRequestId.length > 128)) ||
          (encrypted && (!context.authorized || sid != context.sidB64))) {
        throw const FormatException('Invalid chunk transfer envelope');
      }

      // A transfer that reassembled into another envelope would re-enter this
      // path forever. Nothing legitimate names one, so refuse outright.
      if (kind == ConfigCommand.debrifyChannelStart ||
          kind == ConfigCommand.debrifyChannelChunk ||
          kind == ConfigCommand.debrifyChannelNeed ||
          kind == ConfigCommand.complete) {
        debugPrint('RemoteCommandRouter: refusing recursive chunk transfer');
        return;
      }

      debugPrint(
        'RemoteCommandRouter: chunked transfer started ($totalChunks chunks)',
      );
      if (kind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_start',
          fields: <String, Object?>{
            'trace': diagnosticTrace,
            'chunks': totalChunks,
            'encrypted': encrypted,
          },
        );
      }

      final existing = _chunkBuffers[transferId];
      if (existing != null && existing.peerKey != peer) {
        throw const FormatException('Transfer ID belongs to another peer');
      }
      if (existing == null && _chunkBuffers.length >= 4) {
        throw const FormatException('Too many active transfers');
      }
      existing?.timeout?.cancel();
      // The sender fires its start packet twice (a lost start is the one
      // packet gap-repair cannot recover). A duplicate for a transfer that
      // is already receiving must be a NO-OP — rebuilding the buffer would
      // wipe every chunk that already landed.
      if (existing != null &&
          existing.totalChunks == totalChunks &&
          existing.kind == kind &&
          existing.receivedCount > 0) {
        if (kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunk_start_repeat',
            fields: <String, Object?>{
              'trace': diagnosticTrace,
              'received': existing.receivedCount,
              'chunks': totalChunks,
            },
          );
        }
        _armChunkTimeout(transferId, existing);
        return;
      }

      final buffer = _ChunkBuffer(
        label: label,
        kind: kind,
        totalChunks: totalChunks,
        chunks: List<String?>.filled(totalChunks, null),
        timeout: null,
        encrypted: encrypted,
        sidB64: sid,
        blobN: (data['n'] as num?)?.toInt(),
        // Plain (v1) transfers replay with the SENDER's source context —
        // keyed to null, the reassembled payload's consent entry would never
        // match the complete packet arriving from the real address.
        sourceIp: context.sourceIp,
        peerKey: peer,
        remembered: context.remembered,
        resultRequestId: resultRequestId,
      );
      _chunkBuffers[transferId] = buffer;
      _armChunkTimeout(transferId, buffer);
    } catch (error) {
      if (diagnosticKind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_start_rejected',
          fields: <String, Object?>{
            'trace': diagnosticTrace,
            'errorType': error.runtimeType,
          },
        );
      }
      debugPrint('RemoteCommandRouter: invalid chunk start');
      showSnackBar('Failed to receive transfer', isError: true);
    }
  }

  /// (Re)start a transfer's stall deadline.
  ///
  /// v2 (sealed) transfers repair instead of dying: after a short stall the
  /// receiver names the missing indices over the session and the sender
  /// replays them — this is what makes the sender's aggressive pacing safe.
  /// Plain v1 transfers have no session to carry that request, so they keep
  /// the original single long deadline.
  void _armChunkTimeout(String transferId, _ChunkBuffer buffer) {
    buffer.timeout?.cancel();
    if (!buffer.encrypted) {
      buffer.timeout = Timer(kChunkTransferTimeout, () {
        if (buffer.kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunk_timeout',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'received': buffer.receivedCount,
              'chunks': buffer.totalChunks,
              'encrypted': false,
            },
          );
        }
        debugPrint('RemoteCommandRouter: chunk transfer stalled');
        _chunkBuffers.remove(transferId);
        // A silent drop reads as success from the sender's side, so the
        // receiving end has to be the one that says the data never landed.
        showSnackBar('Transfer timed out: ${buffer.label}', isError: true);
      });
      return;
    }
    buffer.timeout = Timer(kChunkRepairStall, () {
      final missing = <int>[];
      for (
        var i = 0;
        i < buffer.totalChunks && missing.length < kChunkNeedMaxIndices;
        i++
      ) {
        if (buffer.chunks[i] == null) missing.add(i);
      }
      if (missing.isEmpty) return; // completion raced the timer
      final state = RemoteControlState();
      final sid = buffer.sidB64;
      final session = sid == null
          ? null
          : state.sessionManager?.sessionBySid(sid);
      if (buffer.repairRounds >= kChunkRepairMaxRounds || session == null) {
        if (buffer.kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunk_repair_exhausted',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'received': buffer.receivedCount,
              'chunks': buffer.totalChunks,
              'rounds': buffer.repairRounds,
              'sessionReady': session != null,
            },
          );
        }
        debugPrint('RemoteCommandRouter: chunk transfer stalled beyond repair');
        _chunkBuffers.remove(transferId);
        showSnackBar('Transfer timed out: ${buffer.label}', isError: true);
        unawaited(
          _reportChunkFailure(
            buffer,
            'Transfer timed out before the TV could import it',
          ),
        );
        return;
      }
      buffer.repairRounds++;
      if (buffer.kind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_repair_requested',
          fields: <String, Object?>{
            'trace': RemoteTransferDiagnostics.traceToken(
              buffer.resultRequestId,
            ),
            'missing': missing.length,
            'round': buffer.repairRounds,
          },
        );
      }
      debugPrint(
        'RemoteCommandRouter: requesting ${missing.length} missing chunk(s), '
        'repair round ${buffer.repairRounds}',
      );
      // Guarded: sendEncryptedCommand can THROW (profile scope changed
      // mid-transfer), and an unawaited raw future would surface that as an
      // uncaught zone error from a timer callback.
      unawaited(() async {
        try {
          await state.sendEncryptedCommand(
            session,
            RemoteCommand(
              action: RemoteAction.config,
              command: ConfigCommand.debrifyChannelNeed,
              data: chunkNeedBody(transferId: transferId, missing: missing),
            ),
          );
        } catch (error) {
          if (buffer.kind == ConfigCommand.profileGraph) {
            RemoteTransferDiagnostics.record(
              'receiver_chunk_repair_send_exception',
              fields: <String, Object?>{
                'trace': RemoteTransferDiagnostics.traceToken(
                  buffer.resultRequestId,
                ),
                'errorType': error.runtimeType,
              },
            );
          }
          debugPrint('RemoteCommandRouter: repair request send failed');
        }
      }());
      _armChunkTimeout(transferId, buffer);
    });
  }

  /// Handle a single chunk of a chunked channel transfer
  Future<void> handleChunk(
    String jsonData,
    RemoteCommandContext context,
  ) async {
    _ChunkBuffer? failedBuffer;
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final transferId = data['transferId'] as String;
      final index = data['index'] as int;
      final chunkData = data['data'] as String;

      final buffer = _chunkBuffers[transferId];
      if (buffer == null) {
        debugPrint('RemoteCommandRouter: chunk has no active buffer');
        return;
      }
      failedBuffer = buffer;

      if (peerKeyOf(context) != buffer.peerKey ||
          context.encrypted != buffer.encrypted ||
          chunkData.length > kChunkDataMaxBytes + 256) {
        debugPrint('RemoteCommandRouter: chunk peer or size mismatch');
        return;
      }

      // A corrupt or hostile packet must not blow up the receiver.
      if (index < 0 || index >= buffer.totalChunks) {
        debugPrint('RemoteCommandRouter: chunk index is out of range');
        return;
      }

      // Only count if this slot was not already filled (guards against duplicate UDP packets)
      if (buffer.chunks[index] == null) {
        buffer.receivedCount++;
      }
      buffer.chunks[index] = chunkData;
      if (buffer.kind == ConfigCommand.profileGraph) {
        final percent = (buffer.receivedCount * 100) ~/ buffer.totalChunks;
        final bucket = percent >= 100
            ? 100
            : percent >= 75
            ? 75
            : percent >= 50
            ? 50
            : percent >= 25
            ? 25
            : 0;
        if (bucket > buffer.diagnosticProgressBucket) {
          buffer.diagnosticProgressBucket = bucket;
          RemoteTransferDiagnostics.record(
            'receiver_chunk_progress',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'percent': bucket,
              'received': buffer.receivedCount,
              'chunks': buffer.totalChunks,
            },
          );
        }
      }
      // Progress means the transfer is alive — push the stall deadline out.
      _armChunkTimeout(transferId, buffer);

      // Check if all chunks have arrived
      if (buffer.receivedCount >= buffer.totalChunks) {
        buffer.timeout?.cancel();
        _chunkBuffers.remove(transferId);

        // Decode into one bounded byte buffer and release the base64 chunk
        // strings before decrypting or expanding a potentially large graph.
        // Keeping both representations alive through the awaited restore used
        // to add several megabytes to the receiver's peak memory.
        final reassembled = _takeReassembledPayload(buffer);
        final full = reassembled.payload;

        if (buffer.kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunks_complete',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'chunks': buffer.totalChunks,
              'wireBytes': reassembled.bytes,
              'characters': full.length,
            },
          );
        }

        debugPrint(
          'RemoteCommandRouter: All chunks received for ${buffer.label}, '
          'reassembled ${full.length} chars',
        );

        if (buffer.encrypted) {
          await _completeEncryptedBlob(transferId, buffer, full);
          return;
        }

        // Replay through the normal switch, exactly as if the payload had
        // arrived in a single packet — from the same source it actually did.
        await dispatchCommand(
          RemoteAction.config,
          buffer.kind,
          full,
          RemoteCommandContext(
            encrypted: false,
            authorized: false,
            sourceIp: buffer.sourceIp,
          ),
        );
      }
    } catch (error) {
      if (failedBuffer?.kind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_exception',
          fields: <String, Object?>{
            'trace': RemoteTransferDiagnostics.traceToken(
              failedBuffer?.resultRequestId,
            ),
            'errorType': error.runtimeType,
            'received': failedBuffer?.receivedCount,
            'chunks': failedBuffer?.totalChunks,
          },
        );
      }
      debugPrint('RemoteCommandRouter: chunk handling failed');
      final buffer = failedBuffer;
      if (buffer != null) {
        buffer.timeout?.cancel();
        _chunkBuffers.removeWhere(
          (_, candidate) => identical(candidate, buffer),
        );
        await _reportChunkFailure(
          buffer,
          'The TV could not reassemble the transfer',
        );
      }
    }
  }

  ({String payload, int bytes}) _takeReassembledPayload(_ChunkBuffer buffer) {
    final bytes = BytesBuilder(copy: false);
    try {
      for (final chunk in buffer.chunks) {
        final decoded = base64.decode(chunk!);
        if (bytes.length > kMaxRemoteTransferPayloadBytes - decoded.length) {
          throw const FormatException('Reassembled transfer is too large');
        }
        bytes.add(decoded);
      }
      final allBytes = bytes.takeBytes();
      return (payload: utf8.decode(allBytes), bytes: allBytes.length);
    } finally {
      buffer.chunks.fillRange(0, buffer.chunks.length, null);
    }
  }

  /// Decrypt and replay a reassembled v2 blob transfer.
  Future<void> _completeEncryptedBlob(
    String transferId,
    _ChunkBuffer buffer,
    String ctB64,
  ) async {
    final graphDiagnostic = buffer.kind == ConfigCommand.profileGraph;
    final trace = RemoteTransferDiagnostics.traceToken(buffer.resultRequestId);
    final state = RemoteControlState();
    final manager = state.sessionManager;
    final sidB64 = buffer.sidB64;
    final n = buffer.blobN;
    if (manager == null || sidB64 == null || n == null) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_session_fields_missing',
          fields: <String, Object?>{'trace': trace},
        );
      }
      debugPrint('RemoteCommandRouter: Encrypted blob missing session fields');
      await _reportChunkFailure(buffer, 'Transfer session data was incomplete');
      return;
    }
    final session = manager.sessionBySid(sidB64);
    if (session == null) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_session_expired',
          fields: <String, Object?>{'trace': trace},
        );
      }
      // Receiver restarted mid-transfer: the session (and its keys) are gone.
      showSnackBar(
        'Transfer failed: session expired — send again',
        isError: true,
      );
      await _reportChunkFailure(buffer, 'Transfer session expired on TV');
      return;
    }
    if (!session.authorized) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_session_unauthorized',
          fields: <String, Object?>{'trace': trace},
        );
      }
      debugPrint('RemoteCommandRouter: Dropping blob on unauthorized session');
      await _reportChunkFailure(buffer, 'Transfer session was not authorized');
      return;
    }
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_blob_open_start',
        fields: <String, Object?>{
          'trace': trace,
          'wireCharacters': ctB64.length,
        },
      );
    }
    final plaintext = await RemoteSessionCrypto.openBlob(
      key: session.recvKey,
      sid: session.sid,
      n: n,
      transferId: transferId,
      kind: buffer.kind,
      ctB64: ctB64,
    );
    if (plaintext == null) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_open_rejected',
          fields: <String, Object?>{'trace': trace},
        );
      }
      showSnackBar(
        'Transfer failed: could not decrypt ${buffer.label}',
        isError: true,
      );
      await _reportChunkFailure(
        buffer,
        'The TV could not decrypt the transfer',
      );
      return;
    }
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_blob_open_complete',
        fields: <String, Object?>{
          'trace': trace,
          'characters': plaintext.length,
        },
      );
    }
    if (!session.acceptBlob(n)) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_replay_rejected',
          fields: <String, Object?>{'trace': trace},
        );
      }
      debugPrint('RemoteCommandRouter: Replayed blob counter $n, dropping');
      return;
    }
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_dispatch_start',
        fields: <String, Object?>{'trace': trace},
      );
    }
    await dispatchCommand(
      RemoteAction.config,
      buffer.kind,
      plaintext,
      RemoteCommandContext(
        encrypted: true,
        authorized: true,
        remembered: buffer.remembered,
        sidB64: session.sidB64,
        peerFingerprint: session.peerFingerprint,
        peerName: session.peerName,
        sourceIp: buffer.sourceIp,
        reject: (code) async {
          await state.sendEncryptedCommand(
            session,
            RemoteCommand(
              action: RemoteAction.pair,
              command: PairCommand.err,
              data: code,
            ),
          );
        },
      ),
    );
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_dispatch_complete',
        fields: <String, Object?>{'trace': trace},
      );
    }
  }

  Future<bool> _reportChunkFailure(_ChunkBuffer buffer, String message) {
    final requestId = buffer.resultRequestId;
    final sid = buffer.sidB64;
    if (requestId == null || sid == null) return Future<bool>.value(false);
    final state = RemoteControlState();
    final session = state.sessionManager?.sessionBySid(sid);
    if (session == null || !session.authorized) {
      return Future<bool>.value(false);
    }
    final context = RemoteCommandContext(
      encrypted: true,
      authorized: true,
      remembered: buffer.remembered,
      sidB64: session.sidB64,
      peerFingerprint: session.peerFingerprint,
      peerName: session.peerName,
      sourceIp: buffer.sourceIp,
    );
    if (buffer.kind == ConfigCommand.profileGraph) {
      return reportProfileGraphResult(
        context,
        requestId: requestId,
        ok: false,
        message: message,
      );
    }
    return reportRemoteTransferResult(
      context,
      requestId: requestId,
      ok: false,
      message: message,
    );
  }
}

/// Buffer for reassembling chunked channel transfers
class _ChunkBuffer {
  /// Human label for messages while the transfer is in flight.
  final String label;

  /// The config command the reassembled payload belongs to. Senders that
  /// predate the generalized envelope don't name one, so it defaults to the
  /// Debrify TV channel it was originally built for.
  final String kind;

  final int totalChunks;
  final List<String?> chunks;

  /// v2 sealed-blob transfers: the payload is AES-GCM ciphertext bound to
  /// session [sidB64] with counter [blobN]; decrypted after reassembly.
  final bool encrypted;
  final String? sidB64;
  final int? blobN;

  /// Datagram source of a PLAIN (v1) transfer's start packet, so the
  /// reassembled payload replays under the sender's consent identity.
  final String? sourceIp;
  final String peerKey;
  final bool remembered;
  final String? resultRequestId;

  /// Restarted on every chunk that arrives: the deadline is for a *stalled*
  /// transfer, not a slow one. A large payload is paced at 50ms per chunk, so
  /// a fixed deadline would kill transfers that were arriving perfectly.
  Timer? timeout;

  int receivedCount = 0;

  /// Last 25% milestone emitted to the retained transfer diagnostics sink.
  int diagnosticProgressBucket = 0;

  /// Gap-repair rounds already spent (v2 transfers only) — bounds the worst
  /// case on a dead link at roughly rounds × [kChunkRepairStall].
  int repairRounds = 0;

  _ChunkBuffer({
    required this.label,
    required this.kind,
    required this.totalChunks,
    required this.chunks,
    required this.timeout,
    this.encrypted = false,
    this.sidB64,
    this.blobN,
    this.sourceIp,
    required this.peerKey,
    this.remembered = false,
    this.resultRequestId,
  });
}
