"""Reproducible original dotLottie fixtures; no external assets or fonts."""
import json
from copy import deepcopy
from pathlib import Path
import struct
import zipfile
import zlib

ROOT = Path(__file__).parent / 'samples'
ROOT.mkdir(exist_ok=True)

def prop(value):
    return {'a': 0, 'k': value}

def animated(start, end):
    return {'a': 1, 'k': [
        {'t': 0, 's': start, 'e': end, 'o': {'x': .3, 'y': 0}, 'i': {'x': .7, 'y': 1}},
        {'t': 45, 's': end},
    ]}

def transform(w, h):
    return {'o': animated([0], [100]), 'r': prop(0), 'p': prop([w/2, h/2, 0]),
            'a': prop([0, 0, 0]), 's': animated([75, 75, 100], [100, 100, 100])}

def composition(w, h):
    # Original outlined HELLO wordmark, expressed only as rectangle paths.
    letters = {
        'H': ['101', '101', '111', '101', '101'],
        'E': ['111', '100', '110', '100', '111'],
        'L': ['100', '100', '100', '100', '111'],
        'O': ['111', '101', '101', '101', '111'],
    }
    shapes = []
    cell = 12 if w > h else 9
    for index, char in enumerate('HELLO'):
        for y, row in enumerate(letters[char]):
            for x, ink in enumerate(row):
                if ink == '1':
                    shapes.append({'ty': 'rc', 'd': 1, 'p': prop([(index*4+x-9)*cell, (y-2)*cell]),
                                   's': prop([cell*.8, cell*.8]), 'r': prop(2)})
    shapes.append({'ty': 'fl', 'c': prop([.9, .96, 1, 1]), 'o': prop(100), 'r': 1})
    layer = {'ddd': 0, 'ind': 1, 'ty': 4, 'nm': 'Outlined HELLO', 'sr': 1,
             'ks': transform(w, h), 'ao': 0, 'shapes': shapes, 'ip': 0, 'op': 90, 'st': 0, 'bm': 0}
    return {'v': '5.7.4', 'fr': 30, 'ip': 0, 'op': 90, 'w': w, 'h': h, 'nm': 'Hello',
            'ddd': 0, 'assets': [], 'layers': [layer]}

def write(name, version, entries, extras=None):
    folder = 'a' if version == '2.0' else 'animations'
    manifest = {'version': version, 'animations': [
        {'id': key, 'name': key.replace('-', ' ').title(), 'background': '#081020'} for key in entries]}
    with zipfile.ZipFile(ROOT / name, 'w', zipfile.ZIP_DEFLATED) as archive:
        def add(path, content):
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, content)
        add('manifest.json', json.dumps(manifest, separators=(',', ':')))
        for key, value in entries.items():
            add(f'{folder}/{key}.json', json.dumps(value, separators=(',', ':')))
        for key, value in (extras or {}).items():
            add(key, value)

write('hello-landscape.lottie', '2.0', {'hello-landscape': composition(960, 540)})
write('hello-portrait.lottie', '1.0', {'hello-portrait': composition(540, 960)})
write('hello-multiple.lottie', '2.0', {'hello-landscape': composition(960, 540), 'hello-portrait': composition(540, 960)})

def chunk(tag, data):
    return struct.pack('!I', len(data)) + tag + data + struct.pack('!I', zlib.crc32(tag + data))
pixels = b''.join(b'\x00' + bytes([30, 160, 220, 255]) * 16 for _ in range(16))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 16, 16, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
image = composition(960, 540)
image['assets'] = [{'id': 'square', 'w': 16, 'h': 16, 'u': '../i/', 'p': 'square.png', 'e': 0}]
image['layers'].append({'ind': 2, 'ty': 2, 'refId': 'square', 'ks': {'o': prop(100), 'p': prop([470, 340]), 'a': prop([0, 0]), 's': prop([150, 150]), 'r': prop(0)}, 'ip': 0, 'op': 90, 'st': 0, 'sr': 1})
write('hello-image.lottie', '2.0', {'hello-image': image}, {'i/square.png': png})

# Representative gradient and mask artwork, separate from the minimal examples.
features = composition(960, 540)
features['layers'][0]['shapes'][-1] = {
    'ty': 'gf', 'o': prop(100), 'r': 1, 't': 1,
    's': prop([-150, 0]), 'e': prop([150, 0]),
    'g': {'p': 2, 'k': prop([0, .1, .8, 1, 1, 1, .25, .65])},
}
features['layers'][0]['masksProperties'] = [{
    'inv': False, 'mode': 'a', 'o': prop(100),
    'pt': prop({'i': [[0, 0]] * 4, 'o': [[0, 0]] * 4,
                'v': [[-150, -50], [150, -50], [150, 50], [-150, 50]], 'c': True}),
    'x': prop(0),
}]
write('hello-features.lottie', '2.0', {'hello-features': features})

radial = composition(960, 540)
radial['layers'][0]['shapes'][-1] = {
    'ty': 'gf', 'o': prop(100), 'r': 1, 't': 2,
    's': prop([0, 0]), 'e': prop([150, 0]),
    'g': {'p': 2, 'k': prop([0, 1, .9, .4, 1, .2, .6, 1])},
}
write('hello-radial.lottie', '2.0', {'hello-radial': radial})

# Top row: alpha matte keeps the left half. Bottom: inverted matte keeps right.
matte = composition(960, 540)
matte['layers'] = []
for index, y, kind in [(1, 220, 1), (3, 320, 2)]:
    source = deepcopy(radial['layers'][0])
    source.update({'ind': index, 'td': 1, 'nm': 'Left half matte'})
    source['ks']['p'] = prop([480, y, 0])
    source['shapes'] = [
        {'ty': 'rc', 'd': 1, 'p': prop([-80, 0]), 's': prop([160, 100]), 'r': prop(0)},
        {'ty': 'fl', 'c': prop([1, 1, 1, 1]), 'o': prop(100), 'r': 1},
    ]
    target = deepcopy(radial['layers'][0])
    target.update({'ind': index + 1, 'tt': kind, 'nm': 'Matted HELLO'})
    target['ks']['p'] = prop([480, y, 0])
    matte['layers'].extend([source, target])
write('hello-mattes.lottie', '2.0', {'hello-mattes': matte})

# Embed only in the development verification app, never the production bundle.
import base64
(Path(__file__).parent / 'sample_data.dart').write_text(
    '// Generated by generate_samples.py. Development fixtures only.\n'
    'const launchSamples = <String, String>{\n' + ''.join(
        f"  '{file.stem}': '{base64.b64encode(file.read_bytes()).decode()}',\n"
        for file in sorted(ROOT.glob('*.lottie'))) + '};\n')
