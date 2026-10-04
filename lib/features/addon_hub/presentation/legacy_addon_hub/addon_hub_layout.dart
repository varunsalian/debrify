import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';

typedef AddonHubLayoutDeps = ({
  KeyEventResult Function(FocusNode, KeyEvent) onPageKey,
  Widget Function() buildHeader,
  Widget Function() buildFilterBar,
  Widget Function() buildBody,
});

class AddonHubLayout {
  AddonHubLayout(this._deps);
  final AddonHubLayoutDeps _deps;

  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: app.seeAll.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.35,
            colors: [
              Color(0xFF241E44),
              Color(0xFF161327),
              Color(0xFF0F0D1D),
              kSeeAllBg,
            ],
            stops: [0.0, 0.38, 0.68, 1.0],
          ),
        ),
        child: SafeArea(
          // Own scope: directional focus search never leaves the hub (the TV
          // sidebar is reached only via _onPageKey's explicit LEFT exit, and it
          // can still focus back INTO the hub via requestFocus).
          child: FocusScope(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _deps.onPageKey,
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _deps.buildHeader(),
                    _deps.buildFilterBar(),
                    Expanded(child: _deps.buildBody()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
