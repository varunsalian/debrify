#!/usr/bin/env python3
"""IPTV fixtures for the shared manifest checker, including rejected mutations."""
import copy
import json
from pathlib import Path


def self_test(package=None):
    from check_settings_moves import check
    fixtures = Path(__file__).with_name('iptv_verbatim_fixtures')
    config = json.loads((fixtures / 'config.json').read_text())
    for name, case in json.loads((fixtures / 'cases.json').read_text()).items():
        settings = copy.deepcopy(config)
        settings.update(case.get('config', {}))
        errors = check(case['original'], case['sources'], case['rows'],
                       'source', package, context_guard=True, config=settings)
        if bool(errors) == case['passes']:
            raise AssertionError(f'IPTV fixture {name}: {errors}')
        print(f'IPTV self-test {name}: {"PASS" if not errors else "rejected"}')
