import 'package:debrify/features/media_servers/data/plex/plex_account_link.dart';
import 'package:debrify/features/media_servers/data/plex/plex_sign_in.dart';
import 'package:debrify/features/media_servers/models/plex_server_choice.dart';

/// A scripted Plex sign-in: codes, polling and connecting without plex.tv.
const plexHome = PlexServerChoice(
  id: 'home',
  name: 'Home',
  owned: true,
  hasSecureAddress: true,
  hasInsecureLocalAddress: true,
);
const plexFriend = PlexServerChoice(
  id: 'friend',
  name: 'Friend',
  owned: false,
  hasSecureAddress: true,
  hasInsecureLocalAddress: false,
);

class FakePlexAttempt implements PlexSignInAttempt {
  FakePlexAttempt(this.gateway);
  final FakePlexSignIn gateway;
  bool closed = false;
  int codes = 0;

  @override
  Future<({String code, DateTime expiresAt})> newCode() async {
    codes++;
    return (code: 'AB${codes}Z', expiresAt: gateway.now.add(gateway.ttl));
  }

  @override
  Future<List<PlexServerChoice>?> poll() async {
    gateway.activePolls++;
    gateway.maxActivePolls = gateway.activePolls > gateway.maxActivePolls
        ? gateway.activePolls
        : gateway.maxActivePolls;
    gateway.polls++;
    await Future<void>.delayed(Duration.zero);
    gateway.activePolls--;
    if (gateway.expireOnPoll) throw const PlexPinExpired();
    final error = gateway.pollErrors.isEmpty
        ? null
        : gateway.pollErrors.removeAt(0);
    if (error != null) throw error;
    return gateway.polls >= gateway.signInAfterPolls ? gateway.servers : null;
  }

  @override
  Future<bool> connect(
    String serverId, {
    required bool allowInsecureLocal,
    required String label,
  }) async {
    gateway.connects.add((serverId, allowInsecureLocal, label));
    final error = gateway.connectError;
    if (error != null) throw error;
    return gateway.reachable;
  }

  @override
  void close() => closed = true;
}

class FakePlexSignIn implements PlexSignInGateway {
  DateTime now = DateTime(2026, 11, 15);
  Duration ttl = const Duration(minutes: 15);
  List<PlexServerChoice> servers = const [plexHome, plexFriend];
  int signInAfterPolls = 2;
  int polls = 0;
  int activePolls = 0;
  int maxActivePolls = 0;
  bool expireOnPoll = false;
  bool reachable = true;
  Exception? connectError;
  Object? startError;

  /// Thrown by the next polls, in order.
  final pollErrors = <Object>[];
  final connects = <(String, bool, String)>[];
  final attempts = <FakePlexAttempt>[];
  final replaceIds = <String?>[];

  @override
  Future<PlexSignInAttempt> start({String? replaceId}) async {
    replaceIds.add(replaceId);
    final error = startError;
    if (error != null) throw error;
    final attempt = FakePlexAttempt(this);
    attempts.add(attempt);
    return attempt;
  }
}
