/// A Plex server offered during sign-in. Names and flags only, never tokens
/// or addresses, so it is safe to publish as UI state.
class PlexServerChoice {
  const PlexServerChoice({
    required this.id,
    required this.name,
    required this.owned,
    required this.hasSecureAddress,
    required this.hasInsecureLocalAddress,
  });

  final String id;
  final String name;
  final bool owned;

  /// It lists an https address (local, remote or relay).
  final bool hasSecureAddress;

  /// It lists a local address reachable only without encryption.
  final bool hasInsecureLocalAddress;

  @override
  bool operator ==(Object other) =>
      other is PlexServerChoice &&
      other.id == id &&
      other.name == name &&
      other.owned == owned &&
      other.hasSecureAddress == hasSecureAddress &&
      other.hasInsecureLocalAddress == hasInsecureLocalAddress;

  @override
  int get hashCode =>
      Object.hash(id, name, owned, hasSecureAddress, hasInsecureLocalAddress);
}
