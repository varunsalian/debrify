import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart'
    show ProfileSessionOwner;
import '../models/discover_source_state.dart';
import 'discover_bindings.dart';
import 'discover_section.dart';
import 'discover_shell_bridge.dart';

typedef DiscoverSessionLifecycleDeps = ({
  bool Function() mounted,
  bool Function() discoverMode,
  ProfileSessionOwner Function() owner,
});

/// Owns Discover's route bindings and claims a pending list at the original start point.
class DiscoverSessionLifecycle {
  DiscoverSessionLifecycle(this.ref, this._deps, this._section);
  final WidgetRef ref;
  final DiscoverSessionLifecycleDeps _deps;
  final DiscoverSection _section;
  late final DiscoverBindings bindings;

  void initialize() {
    // An MDBList list handed off from the Search tab's Lists mode: start the
    // Discover tab on the MDBList source, focused on that list. The nav
    // rebuilds this screen fresh on every tab switch, so the payload set right
    // before switchTab(18) is present by the time we mount.
    if (_deps.discoverMode()) {
      DiscoverShellBridge.claimMdblistList(
        (choice) => _section.discMdblistList = choice,
      );
    }
    final discoverSession = (
      owner: _deps.owner(),
      viewIdentity: Object(),
      initialSource: _section.discMdblistList == null
          ? DiscoverSources.cw
          : DiscoverSources.mdblist,
      hasHandoff: _section.discMdblistList != null,
    );
    bindings = DiscoverBindings(ref, discoverSession);
    if (_section.discMdblistList != null) {
      unawaited(
        _section.discoverSourceController.rememberCurrent(
          isCurrent: _deps.mounted,
        ),
      );
    }
  }
}
