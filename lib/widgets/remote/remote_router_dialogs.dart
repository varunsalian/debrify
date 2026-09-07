import 'package:flutter/material.dart';

import '../../services/remote_control/remote_command_router.dart';
import '../../services/remote_control/remote_session.dart';
import 'remote_legacy_consent_dialog.dart';
import 'remote_pairing_dialog.dart';
import 'router_busy_dialog.dart';

/// The widgets-side presenter for the three dialogs `RemoteCommandRouter`
/// used to raise out of its own file. The router keeps the decisions (which
/// request gets a dialog, what the answer means); this holds the routes.
///
/// Registered once from `_MyAppState.build()`, beside the router's navigator
/// key — the two travel together, since every route here goes on that key.
class RemoteRouterDialogs implements RouterDialogs {
  const RemoteRouterDialogs();

  @override
  Future<void> showBusy({
    required BuildContext context,
    required String message,
    required ValueNotifier<bool> done,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RouterBusyDialog(message: message, done: done),
    );
  }

  @override
  Future<bool?> showLegacyConsent({
    required BuildContext context,
    required String peer,
    required ValueChanged<BuildContext> onDialogContext,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // Retained so buffer expiry can dismiss the dialog — an answer given
        // after the buffer died must not grant anything.
        onDialogContext(context);
        return RemoteLegacyConsentDialog(peer: peer);
      },
    );
  }

  @override
  void showPairingFallback({
    required GlobalKey<NavigatorState>? Function() navigatorKey,
    required PairingGate gate,
  }) {
    if (gate.hasPresenter) return;
    // Looked up LATE, at the moment of presentation: the always-on listener
    // outlives any one navigator, and the key it holds may only acquire a
    // state after the app tree mounts.
    final navigator = navigatorKey()?.currentState;
    if (navigator == null) {
      debugPrint('RemoteCommandRouter: No navigator for pairing dialog');
      return;
    }
    showRemotePairingDialog(navigator.context, gate);
  }
}
