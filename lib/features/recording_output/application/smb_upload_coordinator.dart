// Upload coordination for finished recordings: scan, pick, upload, retry.
// All I/O arrives through injected closures so tests can drive every branch
// without a device; timers use plain Timer (fake_async drives them).

import 'dart:async';

import '../models/smb_target.dart';
import '../models/smb_upload_models.dart';
import 'smb_contracts.dart';
import 'smb_upload_policy.dart';
import 'smb_uploader.dart';

/// Lists the local recording library (uri order does not matter here).
typedef ListLocalRecordings = Future<List<SmbLocalRecording>> Function();

/// Uris whose recording is still being written and must not upload yet.
typedef ActiveRecordingUris = Future<Set<String>> Function();

/// Removes the local copy after a verified upload; result is ignored.
typedef DeleteLocalRecording = Future<bool> Function(String uri);

/// Owns one upload workflow: periodic scans, the per-file loop, retry-ledger
/// writes, and status publishing. Cancellation goes through SmbCancelToken so
/// an in-flight transfer can stop between chunks.
final class SmbUploadCoordinator {
  SmbUploadCoordinator({
    required SmbUploadSettings settings,
    required SmbUploader uploader,
    required ListLocalRecordings listRecordings,
    required ActiveRecordingUris activeUris,
    required DeleteLocalRecording deleteLocal,
    required int Function() nowMs,
    required String Function() scopeId,
    required void Function(SmbUploadStatus) onStatus,
  }) : _settings = settings,
       _uploader = uploader,
       _listRecordings = listRecordings,
       _activeUris = activeUris,
       _deleteLocal = deleteLocal,
       _nowMs = nowMs,
       _scopeId = scopeId,
       _onStatus = onStatus;

  final SmbUploadSettings _settings;
  final SmbUploader _uploader;
  final ListLocalRecordings _listRecordings;
  final ActiveRecordingUris _activeUris;
  final DeleteLocalRecording _deleteLocal;
  final int Function() _nowMs;
  final String Function() _scopeId;
  final void Function(SmbUploadStatus) _onStatus;

  SmbUploadStatus _status = const SmbUploadStatus();

  /// Sizes seen in the previous scan; a file must appear unchanged in two
  /// consecutive scans before it is considered finished.
  Map<String, int> _seen = const {};

  /// Steady beat and the next first-delay/one-off pass timer; both are set
  /// by [start] and cleared by [stop].
  Timer? _beat;
  Timer? _next;
  bool _stopped = false;
  Future<void>? _inflight;
  SmbCancelToken? _cancel;

  /// The newest published status (also delivered to the onStatus callback).
  SmbUploadStatus get status => _status;

  /// One scan + upload pass. A call while a pass runs returns the running
  /// pass's future instead of starting a second pass.
  Future<void> runOnce() =>
      _inflight ??= _guardedPass().whenComplete(() => _inflight = null);

  /// Timer-started passes are unawaited, so nothing may escape them: an
  /// unexpected storage failure is reported in the status instead.
  Future<void> _guardedPass() async {
    try {
      await _pass();
    } catch (error) {
      _cancel = null;
      _publish(
        SmbUploadStatus(
          phase: SmbUploadPhase.idle,
          lastUploadedName: _status.lastUploadedName,
          lastFailure: SmbFailureKind.other,
          lastMessage: '$error',
          lastRunAtMs: _nowMs(),
        ),
      );
    }
  }

  /// Periodic passes: first after [firstDelay], then every [interval].
  /// Calling it again while running does nothing.
  ///
  /// The steady beat is armed together with the first pass, so later passes
  /// land on the interval grid measured from that first pass. A tick that
  /// arrives while a pass is still running is dropped by the single-pass
  /// guard in [runOnce]: it joins the running pass rather than queueing one.
  void start({
    Duration firstDelay = const Duration(seconds: 30),
    Duration interval = const Duration(minutes: 3),
  }) {
    if (_next != null || _beat != null) return;
    _stopped = false;
    _next = Timer(firstDelay, () {
      // A slow pass delays the next scan instead of queueing a second one,
      // so a hung share can never stack up passes behind the beat.
      _beat = Timer.periodic(interval, (_) => unawaited(runOnce()));
      unawaited(runOnce());
    });
  }

  /// Cancels the timers and the upload in flight (via its SmbCancelToken).
  void stop() {
    _stopped = true;
    _next?.cancel();
    _next = null;
    _beat?.cancel();
    _beat = null;
    _cancel?.cancel();
  }

  /// Settings were saved: drop failed/gave-up records (the ledger write is
  /// awaited before the pass starts, so the fresh pass re-reads them), then
  /// run one pass.
  Future<void> targetChanged() async {
    try {
      final ledger = await _settings.readLedger();
      await _settings.writeLedger(ledger.withoutFailures());
    } catch (_) {
      // A settings store that cannot be read or written just skips the reset;
      // the pass below still runs with whatever the ledger already holds.
    }
    await runOnce();
  }

  Future<void> _pass() async {
    final SmbTarget target;
    try {
      target = await _settings.readTarget();
    } catch (_) {
      return;
    }
    if (!target.enabled || !target.isComplete) {
      _publish(const SmbUploadStatus(phase: SmbUploadPhase.disabled));
      return;
    }

    final scope = _scopeId();
    final List<SmbLocalRecording> list;
    final Set<String> active;
    final SmbUploadLedger ledger;
    final List<SmbLocalRecording> ready;
    final Map<String, int> previous = _seen;
    try {
      list = await _listRecordings();
      active = await _activeUris();
      ledger = await _settings.readLedger();
      ready = smbReadyForUpload(
        current: list,
        previousBytes: previous,
        activeUris: active,
        ledger: ledger,
        nowMs: _nowMs(),
      );
    } catch (error) {
      // Listing failures are shown, never thrown; the next scan tries again.
      _publish(
        SmbUploadStatus(
          phase: SmbUploadPhase.idle,
          lastUploadedName: _status.lastUploadedName,
          lastFailure: SmbFailureKind.other,
          lastMessage: '$error',
          lastRunAtMs: _nowMs(),
        ),
      );
      return;
    }
    _seen = {for (final recording in list) recording.uri: recording.bytes};

    if (ready.isEmpty) {
      // Nothing to do: keep whatever the last run reported.
      _publish(
        SmbUploadStatus(
          phase: SmbUploadPhase.idle,
          lastUploadedName: _status.lastUploadedName,
          lastFailure: _status.lastFailure,
          lastMessage: _status.lastMessage,
          lastRunAtMs: _nowMs(),
        ),
      );
      return;
    }

    String? password;
    try {
      password = await _settings.readPassword();
    } catch (_) {
      password = null;
    }

    final token = SmbCancelToken();
    _cancel = token;
    var ledgerNow = ledger;
    var uploadedName = _status.lastUploadedName;
    var failure = _status.lastFailure;
    var message = _status.lastMessage;
    for (var i = 0; i < ready.length; i++) {
      // stop() or a profile handoff ends the run after the current file.
      if (_stopped || _scopeId() != scope) break;
      final recording = ready[i];
      // The status shows the file in flight plus everything still behind it.
      _publish(
        SmbUploadStatus(
          phase: SmbUploadPhase.uploading,
          currentName: recording.name,
          totalBytes: recording.bytes,
          waiting: ready.length - i,
          lastUploadedName: uploadedName,
          lastFailure: failure,
          lastMessage: message,
          lastRunAtMs: _status.lastRunAtMs,
        ),
      );
      var lastPercent = -1;
      final outcome = await _uploader.upload(
        target: target,
        password: password,
        recording: recording,
        cancel: token,
        onProgress: (sent, total) {
          final percent = total <= 0 ? 0 : (sent * 100 ~/ total).clamp(0, 100);
          if (percent == lastPercent) return;
          lastPercent = percent;
          if (_stopped || _scopeId() != scope) return;
          _publish(
            SmbUploadStatus(
              phase: SmbUploadPhase.uploading,
              currentName: recording.name,
              sentBytes: sent,
              totalBytes: total,
              waiting: ready.length - i,
              lastUploadedName: uploadedName,
              lastFailure: failure,
              lastMessage: message,
              lastRunAtMs: _status.lastRunAtMs,
            ),
          );
        },
      );
      if (outcome case SmbUploaded(:final remotePath)) {
        final previousRecord = ledgerNow[recording.uri];
        ledgerNow = ledgerNow.withRecord(
          SmbUploadRecord(
            uri: recording.uri,
            bytes: recording.bytes,
            state: SmbUploadState.uploaded,
            attempts: previousRecord?.attempts ?? 0,
            remotePath: remotePath,
            updatedAtMs: _nowMs(),
          ),
        );
        await _settings.writeLedger(ledgerNow);
        if (target.deleteLocalAfterUpload && _scopeId() == scope) {
          try {
            await _deleteLocal(recording.uri);
          } catch (_) {
            // A failed delete only leaves the local copy around; the upload
            // itself succeeded and stays recorded.
          }
        }
        // Success clears the earlier failure; copyWith cannot clear nulls,
        // so the run keeps the fields that survive in local variables.
        uploadedName = recording.name;
        failure = null;
        message = null;
        continue;
      }
      final failure_ = outcome as SmbUploadFailed;
      if (failure_.kind == SmbFailureKind.cancelled) {
        // Cancellation writes nothing: the next scan retries from scratch.
        break;
      }
      ledgerNow = ledgerNow.withRecord(
        smbFailedRecord(
          previous: ledgerNow[recording.uri],
          recording: recording,
          kind: failure_.kind,
          message: failure_.message,
          nowMs: _nowMs(),
        ),
      );
      await _settings.writeLedger(ledgerNow);
      failure = failure_.kind;
      message = failure_.message;
      if (stopsSmbRun(failure_.kind)) {
        // Every following file would fail the same way; a run-stopper also
        // drops the inherited name so the banner stays about the failure.
        uploadedName = null;
        break;
      }
    }
    _cancel = null;
    if (_stopped) return;
    _publish(
      SmbUploadStatus(
        phase: SmbUploadPhase.idle,
        lastUploadedName: uploadedName,
        lastFailure: failure,
        lastMessage: message,
        lastRunAtMs: _nowMs(),
      ),
    );
  }

  void _publish(SmbUploadStatus status) {
    if (_stopped) return;
    _status = status;
    _onStatus(status);
  }
}
