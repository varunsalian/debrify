"""Whole-declaration split used only by Step 0 probes and real-config fixtures."""
import csv
import re
from pathlib import Path

SOURCE = 'lib/screens/settings/widgets/settings_widgets.dart'
FEATURE = 'lib/features/settings_widgets/presentation/'
GROUPS = {
 'tokens': 'kSettingsBg kSettingsAccent kSettingsAccent2 kSettingsPanel kSettingsPanel2 kSettingsGreen kSettingsRed kSettingsAmber kSettingsLine kSettingsDim kSettingsDim2 kSettingsMaxWidth',
 'pending_badge': 'WebDavSyncPendingBadge',
 'rows': 'SettingsRowContent SettingsRows',
 'links': 'launchSettingsUrl',
 'page_theme': 'settingsPageTheme _settingsThemeBase _settingsThemeApp _settingsThemeCache _buildSettingsPageTheme pushSettingsPage showSettingsDialog',
 'page_chrome': 'SettingsPageScaffold SettingsPageHeader SettingsBannerTone SettingsInfoBanner',
 'root_chrome': 'SettingsBackground SettingsHeader SettingsSectionLabel',
 'connection_info': 'ConnectionInfo settingsConnectionNeedsAttention settingsConnectionIsReady',
 'connections_summary': 'ConnectionsSummary _ConnectionsSummaryState',
 'connection_card': 'settingsInitialsFor ConnectionCard _ConnectionCardState',
 'section': 'SettingsSection',
 'look_hero': 'SettingsLookHero _SettingsLookHeroState _SettingsSwatches',
 'tile': 'SettingsTile _SettingsTileState',
 'toggle_tile': 'SettingsToggleTile _SettingsToggleTileState',
 'tv_choices': 'TvUiScaleChoice kTvUiScaleChoices tvUiScaleLabel TvRenderQualityChoice kTvRenderQualityChoices tvRenderQualityLabel',
 'select_dropdown': 'SettingsSelectOption SettingsSelectDropdown',
 'info_tile': 'SettingsInfoTile',
 'skeleton': 'SettingsSkeleton _SkeletonHeader _SkeletonSection _SkeletonTile',
 'legacy_mode_dialog': 'showLegacyModeInfoDialog',
}
GROUPS = {g: names.split() for g,names in GROUPS.items()}
EXTERNAL = {
 'utils/tv_reveal.dart': ['tvRevealMinimal'],
 'services/main_page_bridge.dart': ['MainPageBridge'],
 'services/profiles/profile_bootstrap.dart': ['ProfileBootstrap'],
 'theme/app_focus.dart': ['FocusExpression'],
 'theme/app_motion.dart': ['AppMotion'],
 'theme/app_theme.dart': ['AppTheme'],
 'theme/app_surface.dart': ['SurfaceFamily','SeparationModel'],
 'theme/app_theme_scope.dart': ['AppThemeScope'],
 'theme/widgets/parallax_focus.dart': ['ParallaxFocus', 'ParallaxShape'],
 'widgets/shimmer.dart': ['Shimmer'],
 'models/tv_render_quality.dart': ['TvRenderQuality'],
}

def split_sources(original, parsed, groups=GROUPS):
    owner = {n:g for g,names in groups.items() for n in names}
    assert set(owner) == {n['name'] for n in parsed['declarations']}
    chunks = {g:[] for g in groups}
    identifiers = {g:set() for g in groups}
    for node in parsed['declarations']:
        group = owner[node['name']]
        chunks[group].append(node['text'])
        identifiers[group].update(t['text'] for t in node['tokens'] if not t['comment'])
    result = {}
    for group,texts in chunks.items():
        used = identifiers[group]
        imports = []
        if group not in ('links','connection_info','tv_choices'):
            imports.append("import 'package:flutter/material.dart';")
        if used & {'KeyEvent','KeyDownEvent','LogicalKeyboardKey','KeyEventResult'}:
            imports.append("import 'package:flutter/services.dart';")
        if 'launchUrl' in used:
            imports.append("import 'package:url_launcher/url_launcher.dart';")
        for path,names in EXTERNAL.items():
            selected = [n for n in names if n in used]
            if selected:
                show = ' show ' + ', '.join(selected) if path.startswith('services/') else ''
                imports.append(f"import 'package:debrify/{path}'{show};")
        for other,names in groups.items():
            cross = set(names) & used
            if other != group and cross:
                assert not any(n.startswith('_') for n in cross), (group,other,cross)
                imports.append(f"import 'package:debrify/features/settings_widgets/presentation/settings_{other}.dart';")
        result[FEATURE+f'settings_{group}.dart'] = '\n'.join(sorted(imports))+'\n\n'+'\n\n'.join(texts)+'\n'
    result[SOURCE] = '\n'.join(f"export 'package:debrify/features/settings_widgets/presentation/settings_{g}.dart' show "+', '.join(sorted(n for n in names if not n.startswith('_')))+';' for g,names in sorted(groups.items()) if any(not n.startswith('_') for n in names))+'\n'
    return result
