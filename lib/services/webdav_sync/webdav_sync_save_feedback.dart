import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

enum WebDavSavePhase { inactive, syncing, pending, synced }

/// Sender-side publication receipts. Sequence numbers belong to one scheduler;
/// a cycle can acknowledge only writes present when that cycle started.
class WebDavSyncSaveFeedback extends ChangeNotifier {
  static final instance = WebDavSyncSaveFeedback(persistent: true);
  WebDavSyncSaveFeedback({this.persistent = false});
  final bool persistent;
  static const pendingKey = 'debrify_device_webdav_save_pending_v1';
  SharedPreferences? _preferences;
  Future<void> _persistence = Future<void>.value();

  Future<void> initialize() async {
    if (!persistent || _preferences != null) return;
    try {
      _preferences = await SharedPreferences.getInstance();
      if (_preferences!.getBool(pendingKey) == true && revision == 0) {
        revision = 1;
      }
    } catch (_) {
      // Feedback cannot prevent startup; durable sync state owns the data.
    }
  }

  void _persist() {
    final pending = hasPending;
    final prefs = _preferences;
    if (prefs == null) return;
    _persistence = _persistence
        .then((_) async {
          await prefs.setBool(pendingKey, pending);
        })
        .catchError((_) {});
  }

  WebDavSavePhase phase = WebDavSavePhase.inactive;
  int revision = 0;
  int confirmedRevision = 0;
  bool enabled = false;
  bool takingLonger = false;
  Future<void> Function()? retryAction;

  bool get hasPending => revision > confirmedRevision;

  void setEnabled(bool value) {
    enabled = value;
    phase = !value
        ? WebDavSavePhase.inactive
        : hasPending
        ? WebDavSavePhase.pending
        : WebDavSavePhase.inactive;
    notifyListeners();
  }

  void forgetAccount() {
    revision = 0;
    confirmedRevision = 0;
    takingLonger = false;
    setEnabled(false);
    _persist();
  }

  void saved(int sequence) {
    revision = sequence;
    _persist();
    takingLonger = false;
    phase = WebDavSavePhase.syncing;
    notifyListeners();
  }

  void started() {
    if (!enabled || !hasPending) return;
    phase = WebDavSavePhase.syncing;
    notifyListeners();
  }

  void finished(int sequence, {required bool published}) {
    if (published && sequence > confirmedRevision) {
      confirmedRevision = sequence > revision ? revision : sequence;
    }
    _persist();
    if (!enabled) return;
    phase = !hasPending ? WebDavSavePhase.synced : WebDavSavePhase.pending;
    if (!hasPending) takingLonger = false;
    notifyListeners();
  }

  void waiting() {
    if (!enabled || !hasPending) return;
    phase = WebDavSavePhase.pending;
    notifyListeners();
  }

  void timedOut() {
    if (!enabled || !hasPending) return;
    takingLonger = true;
    notifyListeners();
  }

  Future<void> retry() async {
    if (!enabled || !hasPending || phase == WebDavSavePhase.syncing) return;
    started();
    try {
      await retryAction?.call();
    } catch (_) {
      waiting();
    } finally {
      if (hasPending && phase == WebDavSavePhase.syncing) waiting();
    }
  }
}
