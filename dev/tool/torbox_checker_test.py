#!/usr/bin/env python3
"""TorBox fixtures for the shared manifest checker, including rejected mutations."""
import copy
import json
from pathlib import Path


def self_test(package=None):
    from check_settings_moves import check
    fixtures = Path(__file__).with_name('torbox_verbatim_fixtures')
    config = json.loads((fixtures / 'config.json').read_text())
    for name, case in json.loads((fixtures / 'cases.json').read_text()).items():
        settings = copy.deepcopy(config)
        settings.update(case.get('config', {}))
        errors = check(case['original'], case['sources'], case['rows'],
                       'source', package, context_guard=True, config=settings)
        if bool(errors) == case['passes']:
            raise AssertionError(f'TorBox fixture {name}: {errors}')
        print(f'TorBox self-test {name}: {"PASS" if not errors else "rejected"}')


if __name__ == '__main__':
    # Normally run through `check_verbatim_moves.py --self-test`; running this
    # file directly runs the same TorBox fixtures instead of exiting silently.
    self_test()
