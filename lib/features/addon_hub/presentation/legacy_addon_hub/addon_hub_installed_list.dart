import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:flutter/material.dart';

typedef AddonHubInstalledListDeps = ({
  AddonHubInstalledState installedState,
  void Function(VoidCallback) setState,
  bool Function() mounted,
  BuildContext Function() context,
});

class AddonHubInstalledList {
  AddonHubInstalledList(this._deps);
  final AddonHubInstalledListDeps _deps;

  Future<void> setMetadataProvider(String value) async {
    final previous = _deps.installedState.metadataProviderPreference;
    _deps.setState(
      () => _deps.installedState.metadataProviderPreference = value,
    );
    try {
      await _deps.installedState.stremio.setMetadataProviderPreference(value);
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(
        () => _deps.installedState.metadataProviderPreference = previous,
      );
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t save metadata provider: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
