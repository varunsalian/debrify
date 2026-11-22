import 'dart:async';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/ledger_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter/foundation.dart';

import 'ledger_api.dart';
import 'ledger_auth_api.dart';

/// Owns the signed-in session of the active profile on this device: device
/// sign-in, the rotating token pair, and sign-out. It is the
/// [LedgerTokenSource] for [LedgerApi].
///
/// Refresh is single-flight per profile: the refresh token rotates on every
/// exchange and the server revokes the whole session when an exchanged token
/// is presented again, so two concurrent exchanges must never happen.
class LedgerSession implements LedgerTokenSource {
  LedgerSession({LedgerAuthApi? authApi, DateTime Function()? now})
    : _auth = authApi ?? LedgerAuthApi(),
      _now = now ?? DateTime.now;

  final LedgerAuthApi _auth;
  final DateTime Function() _now;

  /// Refresh this long before the access token's stated expiry.
  static const Duration _expiryMargin = Duration(minutes: 2);

  final Map<Object?, Future<bool>> _refreshes = {};
  final Map<String, ({ProfileAsyncAuthorization? authorization})>
  _pendingSignIns = {};

  /// Called after the account behind the session may have changed (sign-in,
  /// sign-out), so account-scoped caches are dropped.
  VoidCallback? onAccountChanged;

  Future<bool> isAuthenticated({bool Function()? canContinue}) async {
    if (canContinue?.call() == false) return false;
    final token = await LedgerStorage.getAccessToken(canContinue: canContinue);
    return token != null && token.isNotEmpty && canContinue?.call() != false;
  }

  Future<String?> username() => LedgerStorage.getUsername();

  // ── LedgerTokenSource ─────────────────────────────────────────────────

  @override
  Future<String?> accessToken() async {
    final token = await LedgerStorage.getAccessToken();
    if (token == null || token.isEmpty) return null;
    final expiryMs = await LedgerStorage.getTokenExpiry();
    if (expiryMs != null &&
        _now()
            .add(_expiryMargin)
            .isAfter(DateTime.fromMillisecondsSinceEpoch(expiryMs))) {
      if (await refresh()) {
        final renewed = await LedgerStorage.getAccessToken();
        if (renewed != null && renewed.isNotEmpty) return renewed;
      }
      // A failed early refresh still lets the request try the old token;
      // the server's 401 then routes through [renewAfterRejection].
    }
    return token;
  }

  @override
  Future<String?> renewAfterRejection(String rejectedToken) async {
    final current = await LedgerStorage.getAccessToken();
    // Another caller already rotated the pair while this request was out.
    if (current != null && current.isNotEmpty && current != rejectedToken) {
      return current;
    }
    if (!await refresh()) return null;
    final renewed = await LedgerStorage.getAccessToken();
    return renewed == null || renewed.isEmpty || renewed == rejectedToken
        ? null
        : renewed;
  }

  /// Exchanges the refresh token for a new pair inside the profile that
  /// asked. Returns false when signed out, on a network failure, or when the
  /// server refused the token (the session is then dead and is forgotten
  /// locally, so the app shows it as disconnected instead of retrying).
  Future<bool> refresh() async {
    // Keyed by the caller's (possibly captured) profile storage, not its
    // session epoch: tokens are stored per profile, so every request of that
    // profile must join the same exchange.
    final key =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture().preferencePrefix
        : null;
    final pending = _refreshes[key];
    if (pending != null) return pending;
    final operation = _refreshInOriginatingProfile();
    _refreshes[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshes[key], operation)) _refreshes.remove(key);
    }
  }

  Future<bool> _refreshInOriginatingProfile() async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      return authorization == null
          ? await _exchange()
          : await authorization.run(_exchange);
    } on StateError {
      return false;
    } catch (error) {
      debugPrint('Ledger: token refresh error (${error.runtimeType})');
      return false;
    }
  }

  Future<bool> _exchange() async {
    final refreshToken = await LedgerStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    final result = await _auth.refresh(refreshToken);
    // Only act if the stored pair is still the one exchanged; a sign-out or
    // re-sign-in during the request must not be overwritten or cleared.
    if (await LedgerStorage.getRefreshToken() != refreshToken) return false;
    final tokens = result.tokens;
    if (tokens == null) {
      // Re-checked right before clearing: a sign-in that committed while the
      // refused exchange was out must survive.
      if (result.rejected &&
          await LedgerStorage.getRefreshToken() == refreshToken) {
        debugPrint('Ledger: refresh token refused; signing out locally');
        await LedgerStorage.clearAuth();
        onAccountChanged?.call();
        MovieProgressStorage.movieFinishedRevision.value++;
      }
      return false;
    }
    await LedgerStorage.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiryMs: tokens.expiryMs,
    );
    return true;
  }

  // ── Device sign-in ────────────────────────────────────────────────────

  /// Starts a device sign-in for the active profile. The completion is later
  /// committed only into this same profile (see [pollSignIn]).
  Future<LedgerDeviceCode?> startSignIn() async {
    final ProfileAsyncAuthorization? authorization;
    try {
      authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
    } on StateError {
      return null;
    }
    final code = await _auth.startDeviceAuthorization();
    if (code == null) return null;
    _pendingSignIns.clear();
    _pendingSignIns[code.deviceCode] = (authorization: authorization);
    return code;
  }

  /// One poll. On approval, stores the session, turns on scrobbling for this
  /// tracker, all inside the originating profile. An attempt that was
  /// cancelled or retired by a profile switch while the poll was out reports
  /// [LedgerPollStatus.denied] and stores nothing.
  Future<LedgerPollStatus> pollSignIn(String deviceCode) async {
    if (!_pendingSignIns.containsKey(deviceCode)) {
      return LedgerPollStatus.denied;
    }
    final result = await _auth.pollDeviceToken(deviceCode);
    final tokens = result.tokens;
    final pending = _pendingSignIns[deviceCode];
    if (pending == null) return LedgerPollStatus.denied;
    if (result.status != LedgerPollStatus.approved || tokens == null) {
      if (result.status == LedgerPollStatus.denied ||
          result.status == LedgerPollStatus.expired) {
        _pendingSignIns.remove(deviceCode);
      }
      return result.status;
    }
    _pendingSignIns.remove(deviceCode);
    Future<void> commit() async {
      await LedgerStorage.setSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiryMs: tokens.expiryMs,
      );
      await TrackingSourceStorage.enableTrackingScrobbleTarget(
        TrackingSource.ledger,
      );
      onAccountChanged?.call();
      MovieProgressStorage.movieFinishedRevision.value++;
    }

    final authorization = pending.authorization;
    try {
      if (authorization == null) {
        await commit();
      } else {
        await authorization.runIfCurrent(commit);
      }
    } on StateError {
      return LedgerPollStatus.denied;
    } catch (error) {
      debugPrint('Ledger: storing the session failed (${error.runtimeType})');
      return LedgerPollStatus.error;
    }
    return LedgerPollStatus.approved;
  }

  void cancelSignIn(String deviceCode) => _pendingSignIns.remove(deviceCode);

  /// Stores the display name once the session works. Best effort.
  Future<void> refreshUsername(LedgerApi api) async {
    try {
      final name = await api.displayName();
      if (name != null) await LedgerStorage.setUsername(name);
    } catch (error) {
      debugPrint('Ledger: username lookup failed (${error.runtimeType})');
    }
  }

  /// Signs out: forgets the session on this device, then revokes it on the
  /// server (best effort; sessions are device-bound, so nothing else uses it).
  Future<void> signOut() async {
    final refreshToken = await LedgerStorage.getRefreshToken();
    await LedgerStorage.clearAuth();
    onAccountChanged?.call();
    MovieProgressStorage.movieFinishedRevision.value++;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _auth.revoke(refreshToken);
    }
  }

  /// Abandons any device sign-in started by the outgoing profile (called by
  /// [LedgerService.resetProfileScope] on a profile switch).
  void abandonPendingSignIns() => _pendingSignIns.clear();
}
