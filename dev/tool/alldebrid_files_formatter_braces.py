"""Reparse only AllDebrid's two exact, validated formatter brace additions.

The ordinary occurrence binder still compares every scope, role and binding.
This removes the sidecar-validated brace tokens before obtaining that AST;
it does not exempt any scope or change the pure helper's method frame.
"""


def canonical_lookup(lookup, rows, source, config, package):
    from check_settings_moves import configured, remove_context_exceptions, sidecar
    from check_verbatim_moves import parse
    from check_settings_moves import all_nodes
    if config.get('feature') != 'lib/features/alldebrid_files':
        raise ValueError('AllDebrid formatter occurrence option used outside AllDebrid')
    if package is None:
        raise ValueError('AllDebrid formatter occurrences require an isolated parser package')
    bridge = 'lib/features/alldebrid_files/presentation/legacy_alldebrid/'
    permitted = {
        '_AllDebridFilesScreenState._dismissLoading':
            (bridge + 'alldebrid_feedback.dart', 'AllDebridFeedback', 'dismissLoading'),
        '_AllDebridFilesScreenState.build':
            (bridge + 'alldebrid_root_layout.dart', 'AllDebridRootLayout', 'build'),
    }
    sources, destinations = {}, {}
    with configured(config):
        for site in sidecar('context_exceptions', 'sites', [], config=config):
            destination = (site['file'], site['owner'], site['method'])
            row = next((r for r in rows if (r['destination_file'], r['destination_class'], r['new_name']) == destination), None)
            if (row is None or permitted.get(row['original_name']) != destination
                    or site['kind'] != 'formatter_if_braces' or site.get('prefix_mode') != 'raw'
                    or 'formatter_if_braces' not in row['allowed_edits'].split(',')):
                raise ValueError('Unregistered AllDebrid formatter occurrence site')
            node = lookup.get(destination)
            if node is None:
                # Like the binder, partial real-declaration fixtures skip absent
                # nodes; the full manifest check independently requires them.
                continue
            if destination in destinations.values():
                raise ValueError('Repeated AllDebrid formatter occurrence declaration')
            filtered = remove_context_exceptions(node, [site], rows, row)
            kept = {t['offset'] for t in filtered['tokens']}
            braces = [t for t in node['tokens'] if t['offset'] not in kept]
            if [t['text'] for t in braces] != ['{', '}']:
                raise ValueError('AllDebrid occurrence adaptation must remove exactly two braces')
            text = node['text'].encode('utf-16-le')
            for token in reversed(braces):
                at = 2 * (token['offset'] - node['start'])
                text = text[:at] + text[at + 2:]
            key = row['original_name']
            sources[key] = 'class ' + node['owner'] + ' { ' + text.decode('utf-16-le') + ' }'
            destinations[key] = destination
    result = dict(lookup)
    parsed = all_nodes(parse(sources, package, occurrence_bindings=True)) if sources else {}
    for identity, destination in destinations.items():
        node = parsed.get((identity, destination[1], destination[2]))
        if node is None:
            raise ValueError('AllDebrid formatter reparse changed method ownership')
        result[destination] = node
    return result
