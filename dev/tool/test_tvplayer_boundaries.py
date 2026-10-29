"""Real-PSI controls for imports, import-free peers and qualified/alias bypasses."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import kotlin_psi_parser as k
from check_tvplayer_boundaries import audit, audited_sources, CONFIG, TV, MAIN, discover_sources


class TvBoundariesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(CONFIG.read_text())
        cls.paths = discover_sources()
        cls.sources = {p: (k.ROOT / p).read_text() for p in audited_sources(cls.config, cls.paths)}
        cls.path = TV + '/TvMediaPipelineController.kt'

    def check(self, sources=None, config=None, paths=None, reason=None):
        errors = audit(sources or self.sources, config or self.config, paths or self.paths)
        if reason:
            self.assertTrue(any(reason in e for e in errors), errors)
        else:
            self.assertEqual([], errors)

    def append_member(self, text):
        sources = dict(self.sources)
        p = self.path
        offset = sources[p].rfind('}')
        sources[p] = sources[p][:offset] + text + sources[p][offset:]
        return sources

    def test_current_tree_and_reviewed_owner_child_hosts(self):
        self.check()

    def test_same_package_peer_bypass(self):
        self.check(self.append_member('\nfun bypass(peer: TvStartupGateController) {}\n'), reason='direct peer bypass:')

    def test_fully_qualified_peer_bypass(self):
        self.check(self.append_member('\nfun bypass(peer: com.debrify.app.tv.TvStartupGateController) {}\n'), reason='direct peer bypass:')

    def test_import_alias_cannot_hide_peer_bypass(self):
        sources = self.append_member('\nfun bypass(peer: GateAlias) {}\n')
        sources[self.path] = sources[self.path].replace('package com.debrify.app.tv',
            'package com.debrify.app.tv\nimport com.debrify.app.tv.TvStartupGateController as GateAlias', 1)
        self.check(sources, reason='direct peer bypass:')

    def test_flutter_ui_engine_and_unknown_flutter_namespace(self):
        for target in ['FlutterActivity', 'io.flutter.embedding.engine.FlutterEngine', 'io.flutter.custom.UnknownType']:
            with self.subTest(target=target):
                self.check(self.append_member('\nfun bypass(value: ' + target + ') {}\n'), reason='forbidden Flutter')

    def test_channel_accessor_exception_is_exact(self):
        sources = dict(self.sources)
        p = TV + '/TvEpisodeMetadataReceiver.kt'
        sources[p] = sources[p].replace('MainActivity.getAndroidTvPlayerChannel()', 'MainActivity.startNativePlayer()', 1)
        self.check(sources, reason='unapproved MainActivity access')

    def test_concrete_activity_reference_is_not_nested_model_exception(self):
        self.check(self.append_member('\nfun bypass(activity: AndroidTvTorrentPlayerActivity) {}\n'),
                   reason='unapproved concrete Activity reference')

    def test_new_host_peer_edge_not_implicitly_allowed(self):
        sources = dict(self.sources)
        sources[self.path] = sources[self.path].replace('interface Host {',
            'interface Host {\nval unexpected: TvSourceSwitchController', 1)
        self.check(sources, reason='unapproved Host edge')

    def test_exclusion_widening_and_stale_entries(self):
        config = copy.deepcopy(self.config)
        config['legacy_exclusions'].append(self.path)
        self.check(config=config, reason='legacy exclusion overlaps')
        config = copy.deepcopy(self.config)
        config['legacy_exclusions'].append(TV + '/DeletedController.kt')
        self.check(config=config, reason='stale reviewed TV source or legacy exclusion')
        config = copy.deepcopy(self.config)
        config['source_set'].append(TV + '/DeletedController.kt')
        self.check(config=config, reason='stale reviewed TV source or legacy exclusion')

    def test_audit_must_cover_discovered_sources(self):
        sources = dict(self.sources)
        del sources[self.path]
        self.check(sources, reason='audited sources differ')

    def check_discovered_bypass(self, path):
        folder = k.evidence_root(k.ROOT) / 'boundary-selftests'
        folder.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=folder) as directory:
            root = Path(directory)
            for name in self.paths:
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text((k.ROOT / name).read_text())
            bypass = root / path
            bypass.parent.mkdir(parents=True, exist_ok=True)
            bypass.write_text('package com.debrify.app.tv\n'
                              'internal class Bypass(val peer: TvStartupGateController)\n')
            decoy_path = MAIN + '/kotlin/other/Unrelated.kt'
            decoy = root / decoy_path
            decoy.parent.mkdir(parents=True, exist_ok=True)
            decoy.write_text('package other\n// package com.debrify.app.tv\n'
                             'val note = "package com.debrify.app.tv"\n')
            paths = discover_sources(root)
            self.assertIn(path, paths)
            self.assertNotIn(decoy_path, paths)
            self.assertEqual(set(self.paths) | {path}, set(paths))
            # A new, unlisted TV source is audited like every reviewed one.
            self.assertIn(path, audited_sources(self.config, paths))
            sources = {p: (root / p).read_text() for p in audited_sources(self.config, paths)}
            self.check(sources, paths=paths, reason='direct peer bypass:')

    def test_nested_peer_bypass_is_discovered_and_rejected(self):
        self.check_discovered_bypass(TV + '/extra/Bypass.kt')

    def test_out_of_directory_same_package_bypass_is_discovered_and_rejected(self):
        self.check_discovered_bypass(MAIN + '/kotlin/elsewhere/Bypass.kt')

    def test_strings_and_comments_do_not_create_type_edges(self):
        self.check(self.append_member('\n// FlutterActivity TvStartupGateController\nval note = "FlutterEngine TvStartupGateController"\n'))
