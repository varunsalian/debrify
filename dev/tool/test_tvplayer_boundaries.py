"""Real-PSI controls for imports, import-free peers and qualified/alias bypasses."""
import copy
import json
from pathlib import Path
import unittest

import check_kotlin_moves as k
from check_tvplayer_boundaries import audit, CONFIG, TV


class TvBoundariesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(CONFIG.read_text())
        cls.sources = {p: (k.ROOT / p).read_text() for p in cls.config['source_set']}
        cls.paths = [str(p.relative_to(k.ROOT)) for p in (k.ROOT / TV).glob('*.kt')]
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

    def test_completed_tree_and_reviewed_owner_child_hosts(self):
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

    def test_unclassified_new_file_and_exclusion_widening(self):
        self.check(paths=self.paths + [TV + '/UnclassifiedController.kt'], reason='unclassified TV source')
        config = copy.deepcopy(self.config)
        config['legacy_exclusions'].append(self.path)
        self.check(config=config, reason='legacy exclusion overlaps')

    def test_strings_and_comments_do_not_create_type_edges(self):
        self.check(self.append_member('\n// FlutterActivity TvStartupGateController\nval note = "FlutterEngine TvStartupGateController"\n'))
