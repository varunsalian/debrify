"""Validate live widget getter types and their composition bindings."""
import re


def validate_sources(sources):
    errors = []
    types = {
        'playlistItem': r'Map<String,\s*dynamic>\s+Function\(\)',
        'onPlaybackStarted': r'VoidCallback\?\s+Function\(\)',
    }
    for path, source in sources.items():
        for name, expected_type in types.items():
            if re.search(r'Function\(\)\??\s+' + name + r'\b', source):
                if not re.search(expected_type + r'\s+' + name + r'\s*[;,]', source):
                    errors.append(f'{path}: {name} getter must preserve its original return nullability')
            for binding in re.findall(name + r':\s*([^\n]+)', composition_records(source)):
                if binding.strip().rstrip(',') != '() => widget.' + name:
                    errors.append(f'{path}: {name} binding must read the live widget without copying or caching')
    return errors


def composition_records(source):
    # Only dependency records have getter-valued bindings. Original service
    # calls elsewhere still receive widget.playlistItem as the original map.
    records = []
    for match in re.finditer(r'PlaylistContent\w+\(\s*\(', source):
        depth = 1
        start = match.end()
        for index in range(start, len(source)):
            char = source[index]
            if char == '(':
                depth += 1
            elif char == ')':
                depth -= 1
                if depth == 0:
                    records.append(source[start:index])
                    break
    return '\n'.join(records)
