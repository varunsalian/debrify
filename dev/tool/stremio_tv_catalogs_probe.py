"""Deterministic ORIGINAL/complete split probes; never writes production code."""
import copy
import csv
import json
import re
from pathlib import Path

SOURCE = 'lib/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart'
FEATURE = 'lib/features/stremio_tv_catalogs/'
BRIDGE = FEATURE + 'presentation/legacy_stremio_tv_catalogs/'
GROUPS = {
    FEATURE + 'data/local_catalog_export.dart': ['LocalCatalogExportPayload', 'LocalCatalogExporter'],
    FEATURE + 'data/local_catalog_importer.dart': ['LocalCatalogImporter'],
    BRIDGE + 'local_catalog_editor_dialog.dart': ['StremioTvLocalCatalogEditorDialog', '_StremioTvLocalCatalogEditorDialogState'],
    BRIDGE + 'local_catalogs_manage_dialog.dart': ['StremioTvLocalCatalogsDialog', '_StremioTvLocalCatalogsDialogState'],
    BRIDGE + 'local_catalog_url_import_dialog.dart': ['_backHopsTo', '_ImportUrlDialog', '_ImportUrlDialogState'],
    BRIDGE + 'local_catalog_json_import_dialog.dart': ['_ImportJsonDialog', '_ImportJsonDialogState'],
    BRIDGE + 'local_catalog_trakt_import_dialog.dart': ['_TraktListSource', '_TraktListSourceExt', '_ImportTraktDialog', '_ImportTraktDialogState'],
    BRIDGE + 'local_catalog_mdblist_import_dialog.dart': ['_MdblistListCategory', '_ImportMdblistDialog', '_ImportMdblistDialogState'],
}
ALIASES = {'_ImportUrlDialog': 'LcUrlDialog', '_ImportJsonDialog': 'LcJsonDialog',
           '_ImportTraktDialog': 'LcTraktDialog', '_ImportMdblistDialog': 'LcMdblistDialog',
           '_backHopsTo': 'lcBackHop'}
PUBLIC = ['LocalCatalogExportPayload', 'LocalCatalogExporter', 'LocalCatalogImporter',
          'StremioTvLocalCatalogEditorDialog', 'StremioTvLocalCatalogsDialog']


def active_config(config):
    config = copy.deepcopy(config)
    owners = {n: f for f, names in GROUPS.items() for n in names}
    config['type_aliases'] = []
    config['file_aliases'] = []
    added = {}
    for name, alias in ALIASES.items():
        f = owners[name]
        widget = name.startswith('_Import')
        if widget:
            config['type_aliases'].append(dict(original_name=name, alias=alias, file=f))
        config['file_aliases'].append(dict(original_name=name, alias=alias, file=f,
                                          kind='widget' if widget else 'value', constructors=[]))
        added.setdefault(f, []).append(alias)
    config['additional_owners'] = [dict(file=f, owner='', names=names) for f, names in added.items()]
    return config


def split_sources(original, parsed):
    owners = {n: f for f, names in GROUPS.items() for n in names}
    chunks = {f: [] for f in GROUPS}
    previous = original.index('class LocalCatalogExportPayload')
    ids = {f: set() for f in GROUPS}
    for node in parsed['declarations']:
        name = node['name']; f = owners[name]
        gap = original[previous:node['start']].strip()
        text = node['text']
        for t in reversed(node['tokens']):
            n = t['text']
            if not t['comment']:
                ids[f].add(n)
                if n in ALIASES and owners[n] != f:
                    i = t['offset'] - node['start']
                    text = text[:i] + ALIASES[n] + text[i + len(n):]
        chunks[f].append((gap + '\n\n' if gap else '') + text)
        if name in ALIASES:
            chunks[f].append(('typedef ' + ALIASES[name] + ' = ' + name + ';') if name.startswith('_Import') else ('const ' + ALIASES[name] + ' = ' + name + ';'))
        previous = node['end']
    external = {
        'services/storage/stremio_catalog_storage.dart': ['StremioCatalogStorage'],
        'models/stremio_addon.dart': ['StremioMeta'],
        'services/mdblist/mdblist_list_source.dart': ['MdblistListSource','MdblistListChoice'],
        'services/mdblist/mdblist_service.dart': ['MdblistService','kMdblistEnabled'],
        'services/trakt/trakt_item_transformer.dart': ['TraktItemTransformer'],
        'services/trakt/trakt_service.dart': ['TraktService'],
        'theme/app_theme_scope.dart': ['AppThemeScope'],
        'screens/stremio_tv/widgets/stremio_tv_repo_browser_dialog.dart': ['StremioTvRepoBrowserDialog'],
        'utils/tv_keys.dart': ['isActivateKey'],
        'widgets/tv_text_field.dart': ['TvTextField'],
    }
    result = {}
    for f, texts in chunks.items():
        symbols = ids[f]; imports=[]
        if symbols & {'TimeoutException'}: imports.append("import 'dart:async';")
        if symbols & {'jsonDecode','jsonEncode','JsonEncoder','utf8'}: imports.append("import 'dart:convert';")
        packages=[]
        if not f.startswith(FEATURE+'data/'):
            packages.append("import 'package:flutter/material.dart';")
        if symbols & {'LogicalKeyboardKey','KeyEvent','KeyDownEvent'}:
            packages.append("import 'package:flutter/services.dart';")
        if 'FilePicker' in symbols: packages.append("import 'package:file_picker/file_picker.dart';")
        if 'http' in symbols: packages.append("import 'package:http/http.dart' as http;")
        for uri, names in external.items():
            if symbols.intersection(names): packages.append(f"import 'package:debrify/{uri}';")
        for other,names in GROUPS.items():
            if other!=f and symbols.intersection(names): packages.append(f"import 'package:debrify/{other[4:]}';")
        result[f]='\n'.join(imports)+ ('\n\n' if imports else '')+'\n'.join(sorted(packages))+'\n\n'+'\n\n'.join(texts)+'\n'
    result[SOURCE]='\n'.join(f"export 'package:debrify/{f[4:]}' show " + ', '.join(n for n in names if n in PUBLIC)+';' for f,names in GROUPS.items() if set(names).intersection(PUBLIC))+'\n'
    return result
