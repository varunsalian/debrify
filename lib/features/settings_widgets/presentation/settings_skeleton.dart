import 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_tokens.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:flutter/material.dart';

/// Loading skeleton, restyled to the flat Stremio panels.
class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonHeader(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Shimmer(width: 140, height: 24),
        SizedBox(height: 10),
        Shimmer(width: 220, height: 13),
      ],
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection();

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Shimmer(width: 120, height: 12),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.line),
          ),
          child: Column(
            children: [
              const _SkeletonTile(),
              Divider(height: 1, color: t.line),
              const _SkeletonTile(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: const [
          Shimmer(
            width: 34,
            height: 34,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          SizedBox(width: 12),
          Expanded(child: Shimmer(height: 14)),
        ],
      ),
    );
  }
}
