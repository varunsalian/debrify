import 'package:flutter/material.dart';

import '../utils/platform_util.dart';

/// Shell tab transitions. Android TV fades in only the selected page, so an
/// outgoing Home cannot keep painting or publishing artwork behind another tab.
/// Apple TV and non-TV layouts retain their existing combined transition.
class AppTabSwitcher extends StatelessWidget {
  const AppTabSwitcher({
    super.key,
    required this.selectedIndex,
    required this.isTelevision,
    required this.entranceAnimation,
    required this.child,
  });

  final int selectedIndex;
  final bool isTelevision;
  final Animation<double> entranceAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final androidTv = isTelevision && PlatformUtil.isAndroidTvCached;
    final switcher = AnimatedSwitcher(
      duration: Duration(milliseconds: isTelevision ? 150 : 350),
      layoutBuilder: androidTv
          ? (current, previous) => Stack(
              alignment: Alignment.center,
              // Unmount outgoing pages in this frame. Keeping Home alive for
              // the fade also keeps its hero timers and post-frame publishers
              // alive, which can overwrite a rapidly reopened Home's artwork.
              children: [if (current != null) current],
            )
          : AnimatedSwitcher.defaultLayoutBuilder,
      transitionBuilder: (child, animation) {
        if (isTelevision) {
          return FadeTransition(opacity: animation, child: child);
        }
        final offsetAnimation =
            Tween<Offset>(
              begin: const Offset(0.02, 0.02),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey<int>(selectedIndex), child: child),
    );
    // The old outer fade reset ALL tab content to zero on each selection,
    // exposing the shell backdrop even beneath normally opaque pages.
    return androidTv
        ? switcher
        : FadeTransition(opacity: entranceAnimation, child: switcher);
  }
}
