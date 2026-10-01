import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/tv_text_field.dart';
import 'stremio_tv_focus_frame.dart';

/// The "New Channel" step: a name field with Create and Back. Focus order
/// and key handling stay with the dialog, which passes its nodes and handlers.
class StremioTvCatalogCreateView extends StatelessWidget {
  const StremioTvCatalogCreateView({
    super.key,
    required this.theme,
    required this.itemName,
    required this.saving,
    required this.nameController,
    required this.nameFocus,
    required this.confirmFocus,
    required this.cancelFocus,
    required this.onFieldKey,
    required this.onButtonKey,
    required this.onCreate,
    required this.onBack,
  });
  final ThemeData theme;
  final String itemName;
  final bool saving;
  final TextEditingController nameController;
  final FocusNode nameFocus;
  final FocusNode confirmFocus;
  final FocusNode cancelFocus;
  final FocusOnKeyEventCallback onFieldKey;
  final FocusOnKeyEventCallback onButtonKey;
  final VoidCallback onCreate;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'New Channel',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a local Stremio TV channel for "$itemName"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          StremioTvFocusFrame(
            focusNode: nameFocus,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: onFieldKey,
              child: TvTextField(
                controller: nameController,
                focusNode: nameFocus,
                autofocus: true,
                textInputAction: TextInputAction.done,
                enabled: !saving,
                // Same chrome the rest of Stremio TV's fields already pass.
                accent: app.youtube.focus,
                keyboardGround: app.youtube.keyboardPanel,
                keyboardInk: app.core.tx,
                keyboardInkOnAccent: app.inkOn(app.youtube.focus),
                onUpArrow: () => cancelFocus.requestFocus(),
                onDownArrow: () => confirmFocus.requestFocus(),
                onSubmitted: (_) {
                  if (nameController.text.trim().isNotEmpty) {
                    confirmFocus.requestFocus();
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Channel name',
                  hintText: 'My Weekend Picks',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Focus(
                  focusNode: confirmFocus,
                  onKeyEvent: onButtonKey,
                  child: StremioTvFocusFrame(
                    focusNode: confirmFocus,
                    child: FilledButton.icon(
                      onPressed: saving ? null : onCreate,
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(saving ? 'Creating...' : 'Create'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Focus(
                  focusNode: cancelFocus,
                  onKeyEvent: onButtonKey,
                  child: StremioTvFocusFrame(
                    focusNode: cancelFocus,
                    child: OutlinedButton(
                      onPressed: saving ? null : onBack,
                      child: const Text('Back'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A focusable option row in the catalog picker.
class StremioTvCatalogActionTile extends StatelessWidget {
  const StremioTvCatalogActionTile({
    super.key,
    required this.theme,
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });
  final ThemeData theme;
  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final isFocused = focusNode.hasFocus;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFocused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: isFocused ? 2 : 1,
                ),
                color: isFocused
                    ? theme.colorScheme.primary.withValues(alpha: 0.08)
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: enabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
