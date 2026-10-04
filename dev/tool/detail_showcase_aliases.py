"""Opt-in file-aware aliases and exact constructor/function/const targets."""


def check_file_aliases(lookup, rows, source_path, config):
    from check_settings_moves import tokens
    errors = []
    for spec in config['file_aliases']:
        name, alias, path = spec['original_name'], spec['alias'], spec['file']
        row = next((r for r in rows if r['original_name'] == name), None)
        if row is None or row['destination_file'] != path or row['new_name'] != name:
            errors.append('File alias owner differs: ' + alias)
            continue
        declarations = {alias: ['typedef', alias, '=', name, ';']} if spec['kind'] == 'widget' else {alias: ['const', alias, '=', name, ';']}
        for constructor in spec.get('constructors', []):
            declarations[constructor['name']] = ['const', constructor['name'], '=', name, '.', constructor['target'], ';']
        for declared, expected in declarations.items():
            node = lookup.get((path, '', declared))
            if node is None or tokens(node) != expected:
                errors.append('File alias declaration/target changed: ' + declared)
        # all_nodes contains both classes and their members. Checking both is
        # deliberate; any violation is rejected before declaration reversal.
        for (file, owner, declared), node in lookup.items():
            if file == '<original>' or (file == path and not owner and declared in declarations):
                continue
            code = [t['text'] for t in node['tokens'] if not t['comment']]
            if file == path and alias in code:
                errors.append('Alias used inside its owner: ' + alias)
            elif file != path and name in code:
                errors.append('Private name used outside its owner: ' + name + ' in ' + file)
    return errors
