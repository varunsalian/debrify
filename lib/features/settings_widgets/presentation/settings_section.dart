import 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Flat panel section: quiet uppercase label above a bordered panel of rows
/// separated by hairlines.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? accentColor;

  /// One line under the header saying what the rows below have in common.
  ///
  /// Optional because most sections are self-evident from their title. It
  /// earns its place where a group's rows LOOK like their neighbours but
  /// answer a different question — Appearance's performance rows next to its
  /// style rows being the case that prompted it.
  final String? blurb;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.accentColor,
    this.blurb,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    // The `settingsGroup` family, and the reason it is capped to fill-or-rule:
    // this is ONE filled container whose rows have zero inter-row gap and an
    // in-place `Border.all`. Dropping both would shift every row by a pixel
    // and dissolve the grouping into an undifferentiated stack — so `space`
    // and `glass` are not on offer, and a look that asks for either is
    // clamped to `rule` by `modelFor` before it reaches here.
    final rule =
        app.surface.modelFor(SurfaceFamily.settingsGroup) ==
        SeparationModel.rule;
    final spotlight = app.id == 'spotlight';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) SettingsSectionLabel(title, color: accentColor),
        if (blurb != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10, right: 8),
            child: Text(
              blurb!,
              style: TextStyle(fontSize: 12, height: 1.4, color: t.dim),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            // A rule look keeps the border — that IS its separation — and
            // loses only the fill. The border width is unchanged either way,
            // which is what keeps the row geometry identical.
            color: rule
                ? Colors.transparent
                : spotlight
                ? app.fade(app.core.tx, app.isLight ? 0.035 : 0.047)
                : t.panel,
            borderRadius: spotlight
                ? app.shape.br(13)
                : BorderRadius.circular(16),
            border: Border.all(color: t.line, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i != 0) Divider(height: 1, thickness: 1, color: t.line),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
