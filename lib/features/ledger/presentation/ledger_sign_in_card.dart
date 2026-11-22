import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme_scope.dart';
import '../application/ledger_sign_in_controller.dart';
import '../models/ledger_brand.dart';
import 'ledger_focus_ring.dart';

/// The signed-out half of the connection card: the login button, then the
/// device code with its link, countdown and Cancel.
class LedgerSignInCard extends ConsumerWidget {
  const LedgerSignInCard({
    super.key,
    required this.primaryFocus,
    required this.onCopyCode,
    required this.onOpenLink,
  });

  final FocusNode primaryFocus;
  final void Function(String code) onCopyCode;
  final void Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerSignInControllerProvider);
    final controller = ref.read(ledgerSignInControllerProvider.notifier);
    if (state case LedgerSignInWaiting()) {
      return _CodePanel(
        state: state,
        onCopyCode: onCopyCode,
        onOpenLink: onOpenLink,
        onCancel: controller.cancel,
      );
    }
    final busy = state is LedgerSignInBusy || state is LedgerSignInDone;
    final app = AppThemeScope.of(context);
    return LedgerFocusRing(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          focusNode: primaryFocus,
          // Busy no-op instead of disabling: a disabled button can't hold
          // DPAD focus, which would strand TV users mid-login.
          onPressed: busy ? () {} : controller.start,
          icon: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: app.core.tx,
                  ),
                )
              : const Icon(Icons.login),
          label: Text(
            busy ? 'Getting code...' : 'Login with $kLedgerDisplayName',
          ),
        ),
      ),
    );
  }
}

class _CodePanel extends StatefulWidget {
  const _CodePanel({
    required this.state,
    required this.onCopyCode,
    required this.onOpenLink,
    required this.onCancel,
  });

  final LedgerSignInWaiting state;
  final void Function(String code) onCopyCode;
  final void Function(String url) onOpenLink;
  final VoidCallback onCancel;

  @override
  State<_CodePanel> createState() => _CodePanelState();
}

class _CodePanelState extends State<_CodePanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Repaints the countdown only; expiry itself is the controller's call.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _countdown() {
    final left = widget.state.expiresAt.difference(DateTime.now());
    if (left.isNegative) return '0m 00s';
    final seconds = left.inSeconds % 60;
    return '${left.inMinutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final state = widget.state;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: app.shape.br(12),
            border: Border.all(color: t.line),
          ),
          child: Column(
            children: [
              Text(
                'Enter this code:',
                style: TextStyle(fontSize: 14, color: t.dim),
              ),
              const SizedBox(height: 8),
              // InkWell so copying is DPAD focusable; plain Text so arrow keys
              // traverse instead of moving a text cursor.
              LedgerFocusRing(
                child: InkWell(
                  autofocus: true,
                  borderRadius: app.shape.br(8),
                  onTap: () => widget.onCopyCode(state.userCode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            state.userCode,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                              fontFamily: 'monospace',
                              color: app.core.tx,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.copy, size: 20, color: t.dim),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LedgerFocusRing(
          child: InkWell(
            borderRadius: app.shape.br(8),
            onTap: () => widget.onOpenLink(state.verificationUriComplete),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Go to ${state.verificationUri}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: t.accent2,
                  decoration: TextDecoration.underline,
                  decorationColor: t.accent2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'on your phone or computer',
          style: TextStyle(fontSize: 13, color: t.dim),
        ),
        const SizedBox(height: 12),
        Text(
          'Code expires in ${_countdown()}',
          style: TextStyle(fontSize: 13, color: t.dim),
        ),
        const SizedBox(height: 16),
        LedgerFocusRing(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
          ),
        ),
      ],
    );
  }
}
