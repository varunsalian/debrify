import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/settings_load_error.dart';
import 'widgets/settings_widgets.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../features/ledger/application/ledger_account_controller.dart';
import '../../features/ledger/application/ledger_sign_in_controller.dart';
import '../../features/ledger/models/ledger_brand.dart';
import '../../features/ledger/presentation/ledger_focus_ring.dart';
import '../../features/ledger/presentation/ledger_linked_trackers.dart';
import '../../features/ledger/presentation/ledger_sign_in_card.dart';

/// Connect, inspect and disconnect the Ledger tracker for this profile.
class LedgerSettingsPage extends ConsumerStatefulWidget {
  const LedgerSettingsPage({super.key});

  @override
  ConsumerState<LedgerSettingsPage> createState() => _LedgerSettingsPageState();
}

class _LedgerSettingsPageState extends ConsumerState<LedgerSettingsPage> {
  // DPAD anchor: the sign-in / sign-out button, whichever is shown. Focus
  // returns here when the code card leaves the tree.
  final FocusNode _primaryFocus = FocusNode(debugLabel: 'ledger-primary');

  static const String _title = '$kLedgerDisplayName Settings';

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('ledger_settings');
  }

  @override
  void dispose() {
    _primaryFocus.dispose();
    super.dispose();
  }

  void _focusPrimaryOnTv() {
    if (!PlatformUtil.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _primaryFocus.context != null) {
        _primaryFocus.requestFocus();
      }
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final t = AppThemeScope.of(context).settings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? t.danger : t.success,
      ),
    );
  }

  Future<void> _signOut() async {
    final result = await ref
        .read(ledgerAccountControllerProvider.notifier)
        .signOut();
    if (!mounted) return;
    if (!result.ok) {
      _snack(
        'This connection is shared. Revoke or transfer profile access '
        'before disconnecting.',
        error: true,
      );
      return;
    }
    MainPageBridge.notifyIntegrationChanged();
    _focusPrimaryOnTv();
    _snack(
      result.fellBackToSmart
          ? 'Logged out from $kLedgerDisplayName. Progress source changed '
                'to Smart.'
          : 'Logged out from $kLedgerDisplayName',
    );
  }

  Future<void> _import(String provider, String name) async {
    final ok = await ref
        .read(ledgerAccountControllerProvider.notifier)
        .startImport(provider);
    _snack(
      ok
          ? 'Importing from $name. New plays appear within a few minutes.'
          : "Couldn't start the import from $name.",
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ledgerSignInControllerProvider, (previous, next) {
      switch (next) {
        case LedgerSignInDone():
          ref.read(ledgerAccountControllerProvider.notifier).reload();
          MainPageBridge.notifyIntegrationChanged();
          _focusPrimaryOnTv();
          _snack('Connected to $kLedgerDisplayName');
        case LedgerSignInExpired():
          _focusPrimaryOnTv();
          _snack('Code expired. Please try again.', error: true);
        case LedgerSignInFailed(:final message):
          _focusPrimaryOnTv();
          _snack(message, error: true);
        case LedgerSignInIdle() when previous is LedgerSignInWaiting:
          _focusPrimaryOnTv();
        default:
          break;
      }
    });
    final account = ref.watch(ledgerAccountControllerProvider);
    return SettingsPageScaffold(
      title: _title,
      body: switch (account) {
        AsyncData(:final value) => _body(value),
        AsyncError() => SettingsLoadError(
          onRetry: () =>
              ref.read(ledgerAccountControllerProvider.notifier).reload(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(LedgerAccountState account) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.sync_rounded,
                  title: '$kLedgerDisplayName Integration',
                  subtitle:
                      'Connect your $kLedgerDisplayName account to keep your '
                      'progress, history and watchlist in sync across devices.',
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              account.connected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: account.connected ? t.success : t.dim2,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.connected
                                        ? 'Connected'
                                        : 'Not connected',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: app.core.tx,
                                    ),
                                  ),
                                  if (account.username != null)
                                    Text(
                                      account.username!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: t.dim,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (account.connected)
                          LedgerFocusRing(
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                focusNode: _primaryFocus,
                                // A busy no-op instead of disabling keeps
                                // DPAD focus on the button.
                                onPressed: account.busy ? () {} : _signOut,
                                icon: const Icon(Icons.logout),
                                label: const Text('Logout'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: t.danger,
                                  side: BorderSide(
                                    color: t.danger.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          LedgerSignInCard(
                            primaryFocus: _primaryFocus,
                            onCopyCode: (code) {
                              Clipboard.setData(ClipboardData(text: code));
                              _snack('Code copied to clipboard');
                            },
                            onOpenLink: (url) => launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (account.connected) ...[
                  const SizedBox(height: 16),
                  LedgerLinkedTrackers(
                    trackers: account.linkedTrackers,
                    busy: account.busy,
                    onImport: _import,
                  ),
                ],
                const SizedBox(height: 16),
                const SettingsInfoBanner(
                  text:
                      'How it works: "Login with $kLedgerDisplayName" shows a '
                      'code on screen. Enter it on your phone or computer at '
                      'the address shown to authorize Debrify.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
