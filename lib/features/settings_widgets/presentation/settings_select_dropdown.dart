import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// One choice inside a [SettingsSelectDropdown].
class SettingsSelectOption {
  final String value;
  final String title;
  final String? subtitle;

  const SettingsSelectOption(this.value, this.title, [this.subtitle]);
}

/// Single-choice dropdown for settings cards — replaces the old
/// RadioListTile stacks (Post-Torrent Action, File Selection, …).
///
/// DPAD notes: the closed field is one focusable node (focus ring comes from
/// the themed `focusedBorder`); OK opens the menu, whose items take DPAD
/// focus natively, and BACK dismisses it. The selected option's subtitle is
/// echoed under the field so the descriptive copy isn't lost when closed.
class SettingsSelectDropdown extends StatelessWidget {
  final List<SettingsSelectOption> options;
  final String value;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  const SettingsSelectDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final SettingsSelectOption? selected = options
        .cast<SettingsSelectOption?>()
        .firstWhere((o) => o!.value == value, orElse: () => null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          focusNode: focusNode,
          // A stale stored value (e.g. removed option) renders as an empty
          // field instead of tripping DropdownButton's value assert.
          initialValue: selected?.value,
          isExpanded: true,
          // Variable item heights so subtitles fit in the open menu.
          itemHeight: null,
          dropdownColor: t.panel2,
          borderRadius: BorderRadius.circular(14),
          // No focusColor: with an InputDecoration the SDK swaps the fill
          // color for it on focus, which would blank the panel fill. Focus
          // is carried by the themed focusedBorder instead.
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.dim),
          decoration: const InputDecoration(),
          // Explicit color (not inherit): the dropdown renders its menu items
          // with this style directly, outside the page's DefaultTextStyle.
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          // Closed field shows just the title; the subtitle lives below.
          selectedItemBuilder: (context) => [
            for (final o in options)
              Align(alignment: Alignment.centerLeft, child: Text(o.title)),
          ],
          items: [
            for (final o in options)
              DropdownMenuItem<String>(
                value: o.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        o.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: o.value == value
                              ? t.accent2
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (o.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          o.subtitle!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: t.dim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        if (selected?.subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              selected!.subtitle!,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: t.dim),
            ),
          ),
        ],
      ],
    );
  }
}
