#!/usr/bin/env python3
"""Exercise the real IPTV-settings size/import registrations without file edits."""
from pathlib import Path
from unittest.mock import patch

import check_search_architecture as guard


def check(path, source):
    with patch.object(Path, 'read_text', return_value=source):
        return guard.violations(guard.ROOT / path)


def main():
    prefix = 'lib/features/iptv_settings/'
    pure = prefix + 'presentation/iptv_settings_tv_button.dart'
    bridge = guard.IPTV_SETTINGS_BRIDGE + 'iptv_settings_url_add.dart'
    service = "import 'package:debrify/services/iptv_service.dart';\n"
    assert any('outside the exact legacy bridge' in x for x in check(pure, service))
    assert not any('outside the exact legacy bridge' in x for x in check(bridge, service))
    assert not check(bridge, service), 'the exact bridge must pass every import rule'
    assert check(guard.IPTV_SETTINGS_BRIDGE.replace('legacy_iptv_settings/', 'legacy_iptv_settings_extra/') + 'fixture.dart', service)
    assert check(bridge, "import 'package:http/http.dart';\n")
    for target in [guard.IPTV_SETTINGS_FACADE, 'lib/features/settings/presentation/settings_tv_layout.dart', 'lib/features/iptv/application/iptv_loading.dart']:
        assert check(bridge, f"import 'package:debrify/{target.removeprefix('lib/')}';\n"), target
    assert not check(bridge, "import 'package:debrify/features/iptv/models/iptv_state.dart';\n")
    for target in ['lib/features/settings/presentation/fixture.dart', 'lib/features/iptv/presentation/fixture.dart']:
        assert any('implementation cross-import' in x for x in check(target, "import 'package:debrify/features/iptv_settings/presentation/fixture.dart';\n"))
    assert any('500-line IPTV settings' in x for x in check(pure, '// line\n' * 501))
    assert check(pure, '// TEMP(iptv_settings)\n')
    if guard.IPTV_SETTINGS_COMPLETE:
        assert any('400-line IPTV settings' in x for x in check(guard.IPTV_SETTINGS_FACADE, '// line\n' * 401))
        assert check(guard.IPTV_SETTINGS_FACADE, '// TEMP(iptv_settings)\n')
    print('IPTV settings real architecture positives and size/import/temporary negatives: PASS')


if __name__ == '__main__':
    main()
