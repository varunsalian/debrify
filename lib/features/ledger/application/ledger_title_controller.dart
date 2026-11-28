import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ledger_brand.dart';
import '../models/ledger_title.dart';
import 'ledger_sign_in_controller.dart';

/// Title operations behind the detail page's sheet. Tests override
/// [ledgerTitleGatewayProvider].
abstract interface class LedgerTitleGateway {
  /// Bumped when the account's tracking state may have changed.
  Listenable get changes;
  bool supports(String imdbId);
  Future<bool> isConnected();

  /// Null when the status could not be read.
  Future<LedgerTitleStatus?> status(LedgerTitleKey key);
  Future<bool> setPlanned(LedgerTitleKey key, bool planned);

  /// Completing marks every aired episode watched; undoing removes every play.
  Future<bool> setCompleted(LedgerTitleKey key, bool completed);
  Future<bool> setDropped(LedgerTitleKey key, bool dropped);

  /// A null [rating] removes it.
  Future<bool> rate(LedgerTitleKey key, int? rating);

  /// Removes every play and saved resume point.
  Future<bool> clearProgress(LedgerTitleKey key);

  factory LedgerTitleGateway.live(LedgerService service) =
      _LiveLedgerTitleGateway;
}

class _LiveLedgerTitleGateway implements LedgerTitleGateway {
  _LiveLedgerTitleGateway(this._service);
  final LedgerService _service;

  @override
  Listenable get changes => _service.revision;

  @override
  bool supports(String imdbId) =>
      kLedgerEnabled && LedgerService.supportsId(imdbId);

  @override
  Future<bool> isConnected() => _service.isAuthenticated();

  @override
  Future<LedgerTitleStatus?> status(LedgerTitleKey key) async {
    final status = await _service.titleStatus(key.imdbId, key.contentType);
    if (status == null) return null;
    final completed = key.contentType == 'series'
        ? status.watched && (await _service.showCompleted(key.imdbId) ?? false)
        : status.watched;
    return LedgerTitleStatus(
      planned: status.onWatchlist,
      completed: completed,
      dropped: status.dropped,
      started: status.watched,
      rating: status.rating,
    );
  }

  @override
  Future<bool> setPlanned(LedgerTitleKey key, bool planned) =>
      _service.setWatchlisted(key.imdbId, key.contentType, listed: planned);

  @override
  Future<bool> setCompleted(LedgerTitleKey key, bool completed) => completed
      ? _service.markWatched(key.imdbId, key.contentType)
      : _service.markUnwatched(key.imdbId, key.contentType);

  @override
  Future<bool> setDropped(LedgerTitleKey key, bool dropped) =>
      _service.setDropped(key.imdbId, key.contentType, dropped: dropped);

  @override
  Future<bool> rate(LedgerTitleKey key, int? rating) =>
      _service.rate(key.imdbId, key.contentType, rating);

  @override
  Future<bool> clearProgress(LedgerTitleKey key) =>
      _service.clearProgress(key.imdbId, key.contentType);
}

final ledgerTitleGatewayProvider = Provider<LedgerTitleGateway>(
  (ref) => LedgerTitleGateway.live(LedgerService.instance),
);

@immutable
class LedgerTitleState {
  const LedgerTitleState({
    required this.available,
    this.status = const LedgerTitleStatus(),
    this.busy = false,
  });

  /// False when the tracker is off, signed out, or cannot name this title:
  /// the detail page then shows no button.
  final bool available;
  final LedgerTitleStatus status;

  /// A change is being sent.
  final bool busy;

  LedgerTitleState copyWith({LedgerTitleStatus? status, bool? busy}) =>
      LedgerTitleState(
        available: available,
        status: status ?? this.status,
        busy: busy ?? this.busy,
      );
}

final ledgerTitleControllerProvider = AsyncNotifierProvider.autoDispose
    .family<LedgerTitleController, LedgerTitleState, LedgerTitleKey>(
      LedgerTitleController.new,
      retry: (count, error) => null,
    );

/// One title's tracker state while its detail page is open. It reloads after
/// each change and whenever the account's tracking state moves (a finished
/// playback). A result that lands after a newer request, or for another
/// profile, is dropped.
class LedgerTitleController extends AsyncNotifier<LedgerTitleState> {
  LedgerTitleController(this.key);
  final LedgerTitleKey key;

  late LedgerTitleGateway _gateway;
  late Object? Function() _scope;
  int _generation = 0;

  @override
  Future<LedgerTitleState> build() async {
    _gateway = ref.watch(ledgerTitleGatewayProvider);
    _scope = ref.watch(ledgerSignInScopeProvider);
    final changes = _gateway.changes;
    changes.addListener(_onAccountChange);
    ref.onDispose(() {
      _generation++;
      changes.removeListener(_onAccountChange);
    });
    return _load(const LedgerTitleStatus());
  }

  /// A read that fails keeps [known] rather than inventing "not tracked".
  Future<LedgerTitleState> _load(LedgerTitleStatus known) async {
    if (!_gateway.supports(key.imdbId) || !await _gateway.isConnected()) {
      return const LedgerTitleState(available: false);
    }
    final status = await _gateway.status(key);
    return LedgerTitleState(available: true, status: status ?? known);
  }

  void _onAccountChange() {
    // Reading state after disposal throws, so the mounted check comes first.
    if (!ref.mounted) return;
    final current = state.value;
    // Our own change reloads when it finishes.
    if (current == null || current.busy) return;
    _reload(++_generation, _scope());
  }

  /// [fresh] forgets the status held so far: it belongs to another profile.
  Future<void> _reload(
    int generation,
    Object? scope, {
    bool fresh = false,
  }) async {
    final known = fresh
        ? const LedgerTitleStatus()
        : state.value?.status ?? const LedgerTitleStatus();
    final next = await AsyncValue.guard(() => _load(known));
    if (!ref.mounted || generation != _generation || _scope() != scope) {
      return;
    }
    state = next;
  }

  Future<bool> setPlanned(bool planned) =>
      _change(() => _gateway.setPlanned(key, planned));

  Future<bool> setCompleted(bool completed) =>
      _change(() => _gateway.setCompleted(key, completed));

  Future<bool> setDropped(bool dropped) =>
      _change(() => _gateway.setDropped(key, dropped));

  Future<bool> rate(int? rating) => _change(() => _gateway.rate(key, rating));

  Future<bool> clearProgress() => _change(() => _gateway.clearProgress(key));

  /// Sends one change, then re-reads the status so the switches show what
  /// the tracker holds. Returns whether the tracker accepted the change.
  Future<bool> _change(Future<bool> Function() send) async {
    final current = state.value;
    if (current == null || !current.available || current.busy) return false;
    final generation = ++_generation;
    final scope = _scope();
    state = AsyncData(current.copyWith(busy: true));
    var ok = false;
    try {
      ok = await send();
    } finally {
      if (ref.mounted && generation == _generation) {
        final now = _scope();
        // After a profile change the status shown belongs to the outgoing
        // profile, so it is read again from nothing for the incoming one.
        await _reload(generation, now, fresh: now != scope);
      }
      _settle();
    }
    return ok;
  }

  /// A reload dropped by a newer request must not leave the sheet busy.
  void _settle() {
    if (!ref.mounted) return;
    final current = state.value;
    if (current != null && current.busy) {
      state = AsyncData(current.copyWith(busy: false));
    }
  }
}
