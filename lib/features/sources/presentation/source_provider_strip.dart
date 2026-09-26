import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../models/source_provider_option.dart';

/// Renders ordered provider/retry choices without resolving sources or services.
class SourceProviderStrip extends StatelessWidget {
  SourceProviderStrip({
    super.key,
    required List<SourceProviderOption> options,
    required this.showAll,
    required this.selectedKey,
    required this.onSelect,
    required this.onRetry,
  }) : options = List.unmodifiable(options);

  final List<SourceProviderOption> options;
  final bool showAll;
  final String? selectedKey;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final dim = app.fade(app.core.tx, 0.55);
    Widget pill({
      required String key,
      required Widget child,
      required bool on,
      required VoidCallback? onTap,
    }) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on ? accent : app.fade(app.core.tx, 0.05),
        borderRadius: app.shape.brPill,
        child: InkWell(
          borderRadius: app.shape.brPill,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: child,
          ),
        ),
      ),
    );

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        children: [
          if (showAll)
            pill(
              key: 'source-pill-all',
              on: selectedKey == null,
              onTap: () => onSelect(null),
              child: Text(
                'All',
                style: TextStyle(
                  color: selectedKey == null ? app.inkOn(accent) : dim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final option in options)
            if (option.retryable)
              pill(
                key: 'source-pill-${option.key}',
                on: false,
                onTap: () => onRetry(option.key),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: option.failed
                              ? Theme.of(context).colorScheme.error
                              : dim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    if (option.retrying)
                      const SizedBox.square(
                        dimension: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    else
                      Icon(
                        Icons.refresh_rounded,
                        size: 14,
                        color: option.failed
                            ? Theme.of(context).colorScheme.error
                            : dim,
                      ),
                  ],
                ),
              )
            else
              pill(
                key: 'source-pill-${option.key}',
                on: selectedKey == option.key,
                onTap: () => onSelect(option.key),
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: selectedKey == option.key ? app.inkOn(accent) : dim,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
