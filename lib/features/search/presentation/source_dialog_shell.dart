import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import 'source_action_chip.dart';

/// Stremio-themed shell for the Sources dialogs: dark glass card, purple icon
/// chip header, optional Enable-all/Disable-all row, scrolling [body], Done.
class SourceDialogShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback? onEnableAll;
  final VoidCallback? onDisableAll;
  const SourceDialogShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    this.onEnableAll,
    this.onDisableAll,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 580),
        child: Container(
          decoration: BoxDecoration(
            color: app.home.dialogBg,
            borderRadius: app.shape.br(22),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          // Group so DPAD directional focus stays inside the dialog and walks
          // the rows/actions in a predictable order (mirrors the debrid action
          // sheet, the app's proven TV-dialog pattern).
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [app.seeAll.accent, app.seeAll.accent2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: app.shape.br(13),
                        ),
                        child: Icon(
                          Icons.dns_rounded,
                          color: app.core.tx,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: app.fade(app.core.tx, 0.5),
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEnableAll != null || onDisableAll != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        if (onEnableAll != null)
                          SourceActionChip(
                            icon: Icons.done_all_rounded,
                            label: 'Enable all',
                            onTap: onEnableAll!,
                          ),
                        if (onDisableAll != null) ...[
                          const SizedBox(width: 8),
                          SourceActionChip(
                            icon: Icons.remove_done_rounded,
                            label: 'Disable all',
                            onTap: onDisableAll!,
                          ),
                        ],
                      ],
                    ),
                  ),
                Flexible(child: body),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SourceActionChip(
                      icon: Icons.check_rounded,
                      label: 'Done',
                      filled: true,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget sourceDialogMessage(BuildContext context, String text) {
  final app = AppThemeScope.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    child: Text(
      text,
      style: TextStyle(color: app.fade(app.core.tx, 0.6), height: 1.4),
    ),
  );
}

Widget sourceDialogLoading(BuildContext context) => SizedBox(
  height: 120,
  child: Center(
    child: CircularProgressIndicator(
      color: AppThemeScope.of(context).home.chromeAccent,
    ),
  ),
);
