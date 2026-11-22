import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage/tracking_source_storage.dart';
import '../models/ledger_tracking.dart';
import 'ledger_sign_in_controller.dart';

/// Account operations behind the settings page. Tests override
/// [ledgerAccountGatewayProvider].
abstract interface class LedgerAccountGateway {
  Future<bool> isConnected();
  Future<String?> username();

  /// Trakt/Simkl accounts linked on the website, null when unavailable.
  Future<List<LedgerLinkedTracker>?> linkedTrackers();
  Future<bool> startImport(String provider);

  /// [ok] is false when the connection could not be released (a shared
  /// owner must revoke or transfer access first). [fellBackToSmart] reports
  /// that the progress source pointed at this tracker and moved to Smart.
  Future<({bool ok, bool fellBackToSmart})> signOut();

  factory LedgerAccountGateway.live(LedgerService service) =
      _LiveLedgerAccountGateway;
}

class _LiveLedgerAccountGateway implements LedgerAccountGateway {
  _LiveLedgerAccountGateway(this._service);
  final LedgerService _service;

  @override
  Future<bool> isConnected() => _service.isAuthenticated();

  @override
  Future<String?> username() => _service.getUsername();

  @override
  Future<List<LedgerLinkedTracker>?> linkedTrackers() async {
    try {
      return await _service.api.linkedTrackers();
    } on LedgerApiException catch (error) {
      debugPrint('Ledger: linked trackers failed (${error.statusCode})');
      return null;
    }
  }

  @override
  Future<bool> startImport(String provider) async {
    try {
      await _service.api.startImport(provider);
      return true;
    } on LedgerApiException catch (error) {
      debugPrint('Ledger: import failed (${error.statusCode})');
      return false;
    }
  }

  @override
  Future<({bool ok, bool fellBackToSmart})> signOut() async {
    try {
      await _service.signOut();
    } catch (error) {
      debugPrint('Ledger: sign-out refused (${error.runtimeType})');
      return (ok: false, fellBackToSmart: false);
    }
    return (
      ok: true,
      fellBackToSmart:
          await TrackingSourceStorage.takeTrackingProgressFallbackNotice(),
    );
  }
}

final ledgerAccountGatewayProvider = Provider<LedgerAccountGateway>(
  (ref) => LedgerAccountGateway.live(LedgerService.instance),
);

@immutable
class LedgerAccountState {
  const LedgerAccountState({
    required this.connected,
    this.username,
    this.linkedTrackers,
    this.busy = false,
  });

  final bool connected;
  final String? username;
  final List<LedgerLinkedTracker>? linkedTrackers;

  /// A sign-out or import is running.
  final bool busy;

  LedgerAccountState copyWith({bool? busy}) => LedgerAccountState(
    connected: connected,
    username: username,
    linkedTrackers: linkedTrackers,
    busy: busy ?? this.busy,
  );
}

final ledgerAccountControllerProvider =
    AsyncNotifierProvider.autoDispose<
      LedgerAccountController,
      LedgerAccountState
    >(LedgerAccountController.new, retry: (count, error) => null);

/// The connection card's state. Loads once per page and reloads after
/// sign-in, sign-out and imports. Profile changes are guarded by the scope
/// check: a load that finishes for another profile is dropped.
class LedgerAccountController extends AsyncNotifier<LedgerAccountState> {
  late LedgerAccountGateway _gateway;
  late Object? Function() _scope;
  int _generation = 0;

  @override
  Future<LedgerAccountState> build() async {
    _gateway = ref.watch(ledgerAccountGatewayProvider);
    _scope = ref.watch(ledgerSignInScopeProvider);
    ref.onDispose(() => _generation++);
    return _load();
  }

  Future<LedgerAccountState> _load() async {
    final connected = await _gateway.isConnected();
    if (!connected) return const LedgerAccountState(connected: false);
    final results = await Future.wait<Object?>([
      _gateway.username(),
      _gateway.linkedTrackers(),
    ]);
    return LedgerAccountState(
      connected: true,
      username: results[0] as String?,
      linkedTrackers: results[1] as List<LedgerLinkedTracker>?,
    );
  }

  Future<void> reload() async {
    final generation = ++_generation;
    final scope = _scope();
    final next = await AsyncValue.guard(_load);
    if (!ref.mounted || generation != _generation || _scope() != scope) {
      return;
    }
    state = next;
  }

  Future<({bool ok, bool fellBackToSmart})> signOut() async {
    final current = state.value;
    if (current == null || current.busy) {
      return (ok: false, fellBackToSmart: false);
    }
    final generation = ++_generation;
    state = AsyncData(current.copyWith(busy: true));
    final result = await _gateway.signOut();
    if (!ref.mounted || generation != _generation) return result;
    await reload();
    _settle();
    return result;
  }

  /// Asks the server to import again from a linked tracker. Returns whether
  /// the server accepted the request.
  Future<bool> startImport(String provider) async {
    final current = state.value;
    if (current == null || current.busy) return false;
    final generation = ++_generation;
    state = AsyncData(current.copyWith(busy: true));
    final ok = await _gateway.startImport(provider);
    if (!ref.mounted || generation != _generation) return ok;
    await reload();
    _settle();
    return ok;
  }

  /// A reload dropped by a profile change must not leave the page busy.
  void _settle() {
    final current = state.value;
    if (ref.mounted && current != null && current.busy) {
      state = AsyncData(current.copyWith(busy: false));
    }
  }
}
