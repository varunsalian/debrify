#!/usr/bin/env python3
"""Build the original analyzer maximum; never accept diagnostics from moved code."""
import argparse
from collections import Counter
import json
from pathlib import Path

from suite_evidence import diagnostics, evidence_dir

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'lib/screens/addons/addon_hub_screen.dart'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    inventory = json.loads(
        (ROOT / 'dev/tool/addon_hub_analyzer_inventory.json').read_text())
    strict = Counter()
    for identity in inventory['identities']:
        strict[(identity['severity'], SOURCE, identity['rule'],
                identity['message'])] += identity['maximum_count']
    combined = diagnostics(options.baseline) | strict
    options.output.write_text('\n'.join(
        ' • '.join([severity, message, path + ':1:1', rule])
        for (severity, path, rule, message), count in sorted(combined.items())
        for _ in range(count)) + '\n')
    print(f'Original maximum: {sum(combined.values())}; strict per-symbol '
          f'maxima: {sum(strict.values())}; no moved-code inputs')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
