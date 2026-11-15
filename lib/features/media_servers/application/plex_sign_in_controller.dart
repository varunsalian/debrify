import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/media_server.dart';
import '../data/plex/plex_account_link.dart';
import '../data/plex/plex_sign_in.dart';
import '../models/media_server_errors.dart';
import '../models/plex_server_choice.dart';
import 'plex_sign_in_providers.dart';

sealed class PlexSignInState {
  const PlexSignInState();
}

class PlexSignInIdle extends PlexSignInState {
  const PlexSignInIdle();
}

/// Waiting for plex.tv, or saving: nothing to choose.
class PlexSignInBusy extends PlexSignInState {
  const PlexSignInBusy();
}

class PlexSignInWaiting extends PlexSignInState {
  const PlexSignInWaiting(this.code, this.expiresAt);
  final String code;
  final DateTime expiresAt;
}

class PlexSignInExpired extends PlexSignInState {
  const PlexSignInExpired();
}

class PlexSignInChoosing extends PlexSignInState {
  const PlexSignInChoosing(this.servers, {this.message});
  final List<PlexServerChoice> servers;
  final String? message;
}

class PlexSignInDone extends PlexSignInState {
  const PlexSignInDone();
}

class PlexSignInFailed extends PlexSignInState {
  const PlexSignInFailed(this.message);
  final String message;
}

final plexSignInControllerProvider =
    NotifierProvider.autoDispose<PlexSignInController, PlexSignInState>(
      PlexSignInController.new,
      retry: (count, error) => null,
    );

/// The plex.tv PIN sign-in for one connect page. Every await is followed by
/// a request-generation and profile-scope check, so a cancelled, replaced or
/// out-of-profile step can neither publish state nor save.
class PlexSignInController extends Notifier<PlexSignInState> {
  late PlexSignInGateway _gateway;
  late DateTime Function() _clock;
  late Future<void> Function(Duration) _delay;
  late Object? Function() _scope;
  int _generation = 0;
  Object? _startScope;
  PlexSignInAttempt? _attempt;
  String? _replaceId;
  String _label = '';

  static const _firstPoll = Duration(seconds: 2);
  static const _slowestPoll = Duration(seconds: 5);

  @override
  PlexSignInState build() {
    _gateway = ref.watch(plexSignInGatewayProvider);
    _clock = ref.watch(plexSignInClockProvider);
    _delay = ref.watch(plexSignInDelayProvider);
    _scope = ref.watch(plexSignInScopeProvider);
    ref.onDispose(() {
      _generation++;
      _closeAttempt();
    });
    return const PlexSignInIdle();
  }

  bool _current(int generation) =>
      ref.mounted && generation == _generation && _scope() == _startScope;

  /// The step is still ours but the profile changed under it.
  bool _profileChanged(int generation) =>
      ref.mounted && generation == _generation && _scope() != _startScope;

  void _abandonForProfile(int generation) {
    if (!_profileChanged(generation)) return;
    _generation++;
    _closeAttempt();
    state = const PlexSignInFailed(_profileChangedMessage);
  }

  static const _profileChangedMessage =
      'The active profile changed. Sign in again from this profile.';

  void _closeAttempt() {
    _attempt?.close();
    _attempt = null;
  }

  /// Starts (or restarts) sign-in from an explicit user action.
  Future<void> start({String? replaceId, String label = ''}) async {
    final generation = ++_generation;
    _closeAttempt();
    _replaceId = replaceId;
    _label = label;
    _startScope = _scope();
    state = const PlexSignInBusy();
    try {
      final attempt = await _gateway.start(replaceId: replaceId);
      if (!_current(generation)) {
        attempt.close();
        return;
      }
      _attempt = attempt;
      await _newCode(generation, attempt);
    } catch (error) {
      if (_current(generation)) state = PlexSignInFailed(_message(error));
    }
  }

  /// After the code expired: a new code in the same attempt.
  Future<void> renewCode() async {
    final attempt = _attempt;
    if (attempt == null || _scope() != _startScope) {
      return start(replaceId: _replaceId, label: _label);
    }
    final generation = ++_generation;
    state = const PlexSignInBusy();
    try {
      await _newCode(generation, attempt);
    } catch (error) {
      if (_current(generation)) state = PlexSignInFailed(_message(error));
    }
  }

  Future<void> _newCode(int generation, PlexSignInAttempt attempt) async {
    final code = await attempt.newCode();
    if (!_current(generation)) return;
    state = PlexSignInWaiting(code.code, code.expiresAt);
    unawaited(_poll(generation, attempt, code.expiresAt));
  }

  /// One request at a time, slowing from 2 s to 5 s between checks.
  Future<void> _poll(
    int generation,
    PlexSignInAttempt attempt,
    DateTime expiresAt,
  ) async {
    var interval = _firstPoll;
    while (_current(generation)) {
      await _delay(interval);
      if (!_current(generation)) return _abandonForProfile(generation);
      if (!_clock().isBefore(expiresAt)) {
        state = const PlexSignInExpired();
        return;
      }
      try {
        final servers = await attempt.poll();
        if (!_current(generation)) return _abandonForProfile(generation);
        if (servers == null) {
          interval = Duration(
            milliseconds: min(
              (interval.inMilliseconds * 1.5).round(),
              _slowestPoll.inMilliseconds,
            ),
          );
          continue;
        }
        await _offer(generation, attempt, servers);
        return;
      } on PlexPinExpired {
        if (_current(generation)) state = const PlexSignInExpired();
        return;
      } on MediaServerUnreachable {
        // A dropped connection to plex.tv: keep waiting for the user.
        interval = _slowestPoll;
      } on MediaServerTimeout {
        interval = _slowestPoll;
      } catch (error) {
        if (error is MediaServerHttpError &&
            (error.status == 429 || error.status >= 500)) {
          // plex.tv is busy: try again later.
          interval = _slowestPoll;
          continue;
        }
        // Refused credentials and malformed answers are not retried.
        if (_current(generation)) state = PlexSignInFailed(_message(error));
        return;
      }
    }
    // Left the loop because the profile changed under it.
    _abandonForProfile(generation);
  }

  Future<void> _offer(
    int generation,
    PlexSignInAttempt attempt,
    List<PlexServerChoice> servers,
  ) async {
    if (servers.isEmpty) {
      state = const PlexSignInFailed(
        'No Plex Media Server is available to this Plex account.',
      );
      return;
    }
    // One server with a secure address is connected straight away; if none
    // of its secure addresses answers, the choice (with the opt-in) shows.
    if (servers.length == 1 && servers.single.hasSecureAddress) {
      state = const PlexSignInBusy();
      final saved = await _connect(
        generation,
        attempt,
        servers.single.id,
        allowInsecureLocal: false,
      );
      if (!_current(generation) || saved != false) return;
      state = PlexSignInChoosing(servers, message: plexUnreachableMessage);
      return;
    }
    state = PlexSignInChoosing(servers);
  }

  /// Connects to the chosen server and saves it.
  Future<void> choose(
    String serverId, {
    required bool allowInsecureLocal,
    String? label,
  }) async {
    final attempt = _attempt;
    final current = state;
    if (attempt == null || current is! PlexSignInChoosing) return;
    if (label != null) _label = label;
    final generation = ++_generation;
    state = const PlexSignInBusy();
    final saved = await _connect(
      generation,
      attempt,
      serverId,
      allowInsecureLocal: allowInsecureLocal,
    );
    if (_current(generation) && saved == false) {
      state = PlexSignInChoosing(
        current.servers,
        message: plexUnreachableMessage,
      );
    }
  }

  /// True when saved, false when unreachable, null after a failure that is
  /// already shown.
  Future<bool?> _connect(
    int generation,
    PlexSignInAttempt attempt,
    String serverId, {
    required bool allowInsecureLocal,
  }) async {
    try {
      if (!_current(generation)) {
        _abandonForProfile(generation);
        return null;
      }
      final saved = await attempt.connect(
        serverId,
        allowInsecureLocal: allowInsecureLocal,
        label: _label,
      );
      if (!_current(generation)) {
        _abandonForProfile(generation);
        return null;
      }
      if (saved) {
        _closeAttempt();
        state = const PlexSignInDone();
      }
      return saved;
    } catch (error) {
      if (_current(generation)) state = PlexSignInFailed(_message(error));
      return null;
    }
  }

  void cancel() {
    _generation++;
    _closeAttempt();
    state = const PlexSignInIdle();
  }

  static String _message(Object error) => switch (error) {
    MediaServerAuthError() =>
      'Plex refused this sign-in. Sign in again with a new code.',
    MediaServerException(:final message) => message,
    StateError() =>
      'This profile is locked, changed or unavailable. Sign in again from this profile.',
    _ => 'Could not sign in to Plex. Check your connection and try again.',
  };
}
