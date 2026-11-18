import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';

/// More engines are in flight; existing rows remain usable beneath the strip.
/// [detail] explains a slower source (a WebDAV server listing its folders).
class SourceSearchProgress extends StatelessWidget {
  const SourceSearchProgress({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final style = TextStyle(fontSize: 11.5, color: app.fade(app.core.tx, 0.55));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Still searching sources…', style: style),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail!, style: style),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// First-load spinner. [detail] says what is still being searched, so a
/// slow server reads as progress rather than a stuck screen.
class SourceLoadingIndicator extends StatelessWidget {
  const SourceLoadingIndicator({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    if (detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final app = AppThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: app.fade(app.core.tx, 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty or failed result message. The view supplies its existing message/color.
class SourceStatusMessage extends StatelessWidget {
  const SourceStatusMessage({
    super.key,
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color),
      ),
    ),
  );
}
