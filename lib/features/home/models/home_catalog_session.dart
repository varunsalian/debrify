import 'home_board_configuration.dart';
import '../../../services/profiles/profile_session_memory.dart';
import 'home_catalog_state.dart';

/// One mounted view in one profile epoch. Bootstrap data is consumed when the
/// provider is created; it is not a second owner of the live catalog state.
class HomeCatalogSession {
  const HomeCatalogSession({
    required this.owner,
    required this.viewIdentity,
    this.initialBoard,
    this.initiallyRefreshing = false,
    this.initialConfiguration = const HomeBoardConfiguration.empty(),
  });

  final ProfileSessionOwner owner;
  final Object viewIdentity;
  final HomeCatalogSnapshot? initialBoard;
  final bool initiallyRefreshing;
  final HomeBoardConfiguration initialConfiguration;

  @override
  bool operator ==(Object other) =>
      other is HomeCatalogSession &&
      other.owner == owner &&
      identical(other.viewIdentity, viewIdentity);

  @override
  int get hashCode => Object.hash(owner, identityHashCode(viewIdentity));
}
