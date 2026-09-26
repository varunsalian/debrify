import 'package:flutter/widgets.dart';

import '../../../widgets/provider_picker_dialog.dart';

/// Provider selection presentation shared by manual binding and playback.
/// Configuration/persistence and provider styling retain their calling owners.
Future<String?> pickSourceProvider(
  BuildContext context, {
  required String cancelledProvider,
  required Future<(List<String>, String?)?> Function() loadConfiguration,
  required ProviderPickerOption Function(String provider) optionFor,
  required Future<void> Function(String provider) remember,
  bool Function()? canContinue,
}) async {
  final configuration = await loadConfiguration();
  if (configuration == null) return cancelledProvider;
  final (configured, def) = configuration;
  if (canContinue != null && (!context.mounted || !canContinue())) {
    return cancelledProvider;
  }
  if (configured.isEmpty) return null;
  if (def != null) return def;
  if (configured.length == 1) return configured.first;
  if (!context.mounted) return cancelledProvider;
  final result = await showProviderPickerDialog(context, [
    for (final p in configured) optionFor(p),
  ]);
  if (canContinue != null && (!context.mounted || !canContinue())) {
    return cancelledProvider;
  }
  if (result == null) return cancelledProvider; // dismissed
  // "Remember my choice" persists the default so we never ask again.
  if (result.remember) {
    await remember(result.provider);
  }
  return result.provider;
}
