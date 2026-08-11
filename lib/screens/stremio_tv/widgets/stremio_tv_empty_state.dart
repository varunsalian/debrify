import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';
import '../../../services/main_page_bridge.dart';

class StremioTvEmptyState extends StatelessWidget {
  const StremioTvEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: app.stremioTv.surfaceFill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: app.stremioTv.hairline,
                  width: 0.5,
                ),
              ),
              child: Icon(
                Icons.smart_display_rounded,
                size: 40,
                color: app.core.tx.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Catalog Addons',
              style: TextStyle(
                color: app.core.tx,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Install Stremio catalog addons (like Cinemeta) to discover '
              'channels. Each catalog becomes a TV channel with rotating content.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: app.core.tx.withValues(alpha: 0.55),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (isActivateKey(event.logicalKey)) {
                  MainPageBridge.switchTab?.call(7);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: () => MainPageBridge.switchTab?.call(7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: focused
                            ? app.core.tx.withValues(alpha: 0.14)
                            : app.core.tx.withValues(alpha: 0.08),
                        borderRadius: app.shape.br(14),
                        border: Border.all(
                          color: focused
                              ? app.core.tx.withValues(alpha: 0.5)
                              : app.core.tx.withValues(alpha: 0.12),
                          width: focused ? 1.5 : 0.5,
                        ),
                        boxShadow: focused
                            ? [
                                BoxShadow(
                                  color: app.core.tx.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.extension_rounded,
                              size: 18,
                              color: app.core.tx.withValues(
                                  alpha: focused ? 0.9 : 0.7)),
                          const SizedBox(width: 10),
                          Text(
                            'Go to Addons',
                            style: TextStyle(
                              color: app.core.tx.withValues(
                                  alpha: focused ? 1.0 : 0.85),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
