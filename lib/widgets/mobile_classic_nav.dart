import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme_scope.dart';

/// The "classic" phone navigation — Concept 2 ("Your Five") from
/// design/mockups/phone_nav_mockup/: a persistent Material-style bottom bar of
/// [Home] [three user-chosen slots] [More], with everything else one sheet
/// away. Chosen in Settings → Navigation; the floating glass button remains
/// the alternative style.
///
/// Contract with the host:
///  - Mount as the Scaffold's `bottomNavigationBar` — Scaffold then owns the
///    geometry: the body is inset above the bar, descendant MediaQuery loses
///    the bottom padding the bar absorbs, and fixed SnackBars ("press back
///    again to exit") anchor ABOVE the bar instead of covering it.
///  - Everything speaks REAL tab indices (the load-bearing kind that
///    switchTab() and deep links use) — never positions.
///  - [barIndices] is the validated middle-slot list the host computed
///    (stored picks filtered to visible, backfilled from defaults); this
///    widget renders, it never decides visibility.
///  - When the active tab lives in the sheet, the More slot MORPHS into it
///    (icon + label, highlighted, caret hint) so "where am I" always shows.
class MobileClassicNav extends StatelessWidget {
  /// Bar chrome height, excluding the device's bottom safe inset (which the
  /// bar absorbs itself via its own padding).
  static const double barHeight = 64;

  static const int homeIndex = 15;

  final int currentIndex;

  /// Every destination currently visible to this user, section-ordered.
  final List<int> visibleIndices;

  /// The middle slots (validated by the host; length 0–3, all visible,
  /// never [homeIndex]).
  final List<int> barIndices;

  final List<IconData> icons;
  final List<String> titles;
  final ValueChanged<int> onTap;
  final ValueChanged<List<int>> onBarEdited;
  final VoidCallback? onRemoteControlTap;

  const MobileClassicNav({
    super.key,
    required this.currentIndex,
    required this.visibleIndices,
    required this.barIndices,
    required this.icons,
    required this.titles,
    required this.onTap,
    required this.onBarEdited,
    this.onRemoteControlTap,
  });

  List<int> get _barSlots => [
    if (visibleIndices.contains(homeIndex)) homeIndex,
    ...barIndices,
  ];

  List<int> get _sheetIndices => [
    for (final index in visibleIndices)
      if (!_barSlots.contains(index)) index,
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final slots = _barSlots;
    final sheet = _sheetIndices;
    final activeInSheet = sheet.contains(currentIndex);

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: app.shell.barBg,
        border: Border(
          top: BorderSide(color: app.fade(app.core.tx, 0.08)),
        ),
      ),
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: [
            for (final index in slots)
              _NavSlot(
                icon: icons[index],
                label: titles[index],
                active: currentIndex == index,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(index);
                },
              ),
            if (sheet.isNotEmpty)
              _NavSlot(
                icon: activeInSheet
                    ? icons[currentIndex]
                    : Icons.grid_view_rounded,
                label: activeInSheet ? titles[currentIndex] : 'More',
                active: activeInSheet,
                showCaret: activeInSheet,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openMoreSheet(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── More sheet ────────────────────────────────────────────────────────────

  void _openMoreSheet(BuildContext context) {
    final app = AppThemeScope.of(context);
    final sheet = _sheetIndices;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.shell.navSheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        // Scrollable: short/narrow desktop windows can push the grid past
        // the sheet's 9/16 height cap.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: app.fade(app.core.tx, 0.18),
                  borderRadius: app.shape.br(2),
                ),
              ),
              Row(
                children: [
                  Text(
                    'ALL OF DEBRIFY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: app.fade(app.core.tx, 0.35),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      // The bar can unmount while the sheet is up (rotate to
                      // landscape / widen past the desktop breakpoint) — its
                      // element is then dead and must not open anything.
                      if (context.mounted) _openEditSheet(context);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text('Edit bar'),
                    style: TextButton.styleFrom(
                      foregroundColor: app.shell.navLabel,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
                children: [
                  for (final index in sheet)
                    _SheetCell(
                      icon: icons[index],
                      label: titles[index],
                      active: currentIndex == index,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onTap(index);
                      },
                    ),
                ],
              ),
              if (onRemoteControlTap != null) ...[
                const SizedBox(height: 12),
                _RemoteRow(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onRemoteControlTap!();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Edit sheet ────────────────────────────────────────────────────────────

  void _openEditSheet(BuildContext context) {
    final app = AppThemeScope.of(context);
    // Working copy; persisted only on Done, and only when TOUCHED — a
    // look-and-close Done must stay a no-op: barIndices is the HEALED bar,
    // and persisting it unchanged would overwrite stored picks for
    // currently-gated tabs (which must return when re-enabled) and freeze
    // never-customized users onto today's defaults.
    var picks = List<int>.from(barIndices);
    var dirty = false;
    final candidates = [
      for (final index in visibleIndices)
        if (index != homeIndex) index,
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.shell.navSheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void toggle(int index) {
            HapticFeedback.selectionClick();
            setSheetState(() {
              if (picks.contains(index)) {
                picks.remove(index);
                dirty = true;
              } else if (picks.length < 3) {
                picks.add(index);
                dirty = true;
              }
            });
          }

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.18),
                        borderRadius: app.shape.br(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'EDIT NAVIGATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: app.fade(app.core.tx, 0.35),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          if (dirty) onBarEdited(picks);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: app.shell.navLabel,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'IN YOUR BAR — pick up to 3 (Home and More are fixed)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: const Color(0xFFF5C042).withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: app.shape.br(14),
                      border: Border.all(
                        color: const Color(0xFFF5C042).withValues(alpha: 0.3),
                        width: 1.4,
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _EditChip(
                          icon: icons[homeIndex],
                          label: titles[homeIndex],
                          fixed: true,
                        ),
                        for (final index in picks)
                          _EditChip(
                            icon: icons[index],
                            label: titles[index],
                            onTap: () => toggle(index),
                          ),
                        const _EditChip(
                          icon: Icons.grid_view_rounded,
                          label: 'More',
                          fixed: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'IN THE MENU',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: app.fade(app.core.tx, 0.3),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: app.shape.br(14),
                      border: Border.all(
                        color: app.fade(app.core.tx, 0.12),
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final index in candidates)
                          if (!picks.contains(index))
                            _EditChip(
                              icon: icons[index],
                              label: titles[index],
                              dimmedWhenFull: picks.length >= 3,
                              onTap: () => toggle(index),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Tap to move · a tab that gets disabled later falls '
                      'back to the defaults',
                      style: TextStyle(
                        fontSize: 10,
                        color: app.fade(app.core.tx, 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

class _NavSlot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool showCaret;
  final VoidCallback onTap;

  const _NavSlot({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.showCaret = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              Container(
                width: 48,
                height: 28,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  borderRadius: app.shape.br(14),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1).withValues(alpha: 0.32),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.32),
                    ],
                  ),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: active
                      ? app.shell.navLabel
                      : app.fade(app.core.tx, 0.5),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? app.shell.navLabel
                        : app.fade(app.core.tx, 0.4),
                  ),
                ),
              ],
            ),
            if (showCaret)
              Positioned(
                top: 5,
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 11,
                  color: app.fade(app.core.tx, 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SheetCell({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: app.shape.br(12),
      child: Container(
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.16)
              : app.fade(app.core.tx, 0.045),
          borderRadius: app.shape.br(12),
          border: Border.all(
            color: active
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
                : app.fade(app.core.tx, 0.06),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: active
                  ? app.shell.navLabel
                  : app.fade(app.core.tx, 0.75),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: active
                    ? app.shell.navLabel
                    : app.fade(app.core.tx, 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteRow extends StatelessWidget {
  final VoidCallback onTap;
  const _RemoteRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: app.shape.br(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.045),
          borderRadius: app.shape.br(12),
          border: Border.all(color: app.fade(app.core.tx, 0.06)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.settings_remote_rounded,
              size: 18,
              color: app.fade(app.core.tx, 0.75),
            ),
            const SizedBox(width: 10),
            const Text(
              'Remote control',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: app.fade(app.core.tx, 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool fixed;
  final bool dimmedWhenFull;
  final VoidCallback? onTap;

  const _EditChip({
    required this.icon,
    required this.label,
    this.fixed = false,
    this.dimmedWhenFull = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, fixed ? 0.03 : 0.06),
        borderRadius: app.shape.br(10),
        border: Border.all(
          color: app.fade(app.core.tx, 0.1),
          style: fixed ? BorderStyle.none : BorderStyle.solid,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: app.fade(app.core.tx, fixed ? 0.35 : 0.8),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: app.fade(app.core.tx, fixed ? 0.35 : 0.85),
            ),
          ),
        ],
      ),
    );
    if (fixed || onTap == null) return chip;
    return Opacity(
      opacity: dimmedWhenFull ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: app.shape.br(10),
        child: chip,
      ),
    );
  }
}
