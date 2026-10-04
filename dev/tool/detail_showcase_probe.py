"""Deterministic whole-declaration alias probe; never edits production files."""
import json
from pathlib import Path

FEATURE = 'lib/features/detail_showcase/presentation/'
SOURCE = 'lib/widgets/detail/showcase_parts.dart'


def split_sources(original, parsed, layout):
    groups, aliases = layout['groups'], layout['aliases']
    owner = {name: group for group, names in groups.items() for name in names}
    chunks = {group: [] for group in groups}
    previous = original.index('\n\n///') + 2
    for node in parsed['declarations']:
        group = owner[node['name']]
        gap = original[previous:node['start']].strip()
        text = node['text']
        for token in reversed(node['tokens']):
            name = token['text']
            if not token['comment'] and name in aliases and owner[name] != group:
                i = token['offset'] - node['start']
                text = text[:i] + aliases[name] + text[i + len(name):]
        if gap:
            text = gap + '\n\n' + text
        chunks[group].append(text)
        name = node['name']
        if name in aliases:
            alias = aliases[name]
            if name[1].isupper():
                constructor = 'showcase' + name[1:] + 'Constructor'
                chunks[group].append(f'typedef {alias} = {name};\nconst {constructor} = {name}.new;')
                if name == '_Circle':
                    chunks[group].append('const showcaseCircleMarkConstructor = _Circle.mark;')
            else:
                chunks[group].append(f'const {alias} = {name};')
        previous = node['end']
    external = {
        'models/stremio_addon.dart': ['StremioMeta'],
        'services/debrify_image_cache.dart': ['DebrifyImageCache'],
        'services/imdb_enrichment_service.dart': ['CastMember', 'UniverseTitle', 'DidYouKnowEntry'],
        'services/imdb_parents_guide_service.dart': ['ParentsGuideResult','ParentsGuideCategory','ParentsGuideItem'],
        'services/series_source_service.dart': ['SeriesSource'],
        'services/trakt/trakt_episode_model.dart': ['TraktEpisode'],
        'theme/app_theme.dart': ['AppTheme'],
        'theme/app_theme_scope.dart': ['AppThemeScope'],
        'theme/widgets/parallax_focus.dart': ['ParallaxFocus','ParallaxShape'],
        'utils/platform_util.dart': ['PlatformUtil'],
        'utils/tv_keys.dart': ['TvHoldOk','isActivateOrSpaceKey'],
        'utils/wide_touch_scale.dart': ['wideTouchScale'],
        'widgets/episodes_panel.dart': ['EpisodesPanelView'],
        'widgets/season_action_region.dart': ['SeasonActionRegion'],
        'widgets/tracker_brand_marks.dart': ['TraktMark','SimklMark','MdblistMark','kTraktRed','kSimklBlue','kMdblistPurple'],
        'widgets/viewport_artwork_scope.dart': ['ViewportArtworkScope'],
        'widgets/detail/detail_model.dart': ['DetailModel'],
    }
    import re
    sources = {}
    for group, texts in chunks.items():
        code = '\n\n'.join(texts)
        identifiers = {t['text'] for n in parsed['declarations'] if owner[n['name']] == group for t in n['tokens'] if not t['comment']}
        identifiers.update(aliases[n] for n in list(identifiers) if n in aliases and owner[n] != group)
        imports = ["import 'package:flutter/material.dart';"]
        if identifiers & {'HapticFeedback','LogicalKeyboardKey','KeyDownEvent','KeyEvent'}:
            imports.append("import 'package:flutter/services.dart';")
        if 'CachedNetworkImage' in identifiers:
            imports.append("import 'package:cached_network_image/cached_network_image.dart';")
        for uri, symbols in external.items():
            used = [n for n in symbols if n in identifiers]
            if used:
                show = ' show ' + ', '.join(used) if uri.startswith('services/') else ''
                imports.append(f"import 'package:debrify/{uri}'{show};")
        for other, names in groups.items():
            if other == group:
                continue
            if any(n in identifiers for n in names):
                imports.append(f"import 'package:debrify/features/detail_showcase/presentation/showcase_{other}.dart';")
        sources[FEATURE + f'showcase_{group}.dart'] = '\n'.join(sorted(imports)) + '\n\n' + code + '\n'
    public = [n['name'] for n in parsed['declarations'] if not n['name'].startswith('_')]
    sources[SOURCE] = '\n'.join(f"export 'package:debrify/features/detail_showcase/presentation/showcase_{group}.dart' show " + ', '.join(n for n in names if n in public) + ';' for group, names in groups.items() if any(n in public for n in names)) + '\n'
    return sources
