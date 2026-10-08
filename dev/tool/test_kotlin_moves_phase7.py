"""Phase-7 production fixture: exact guide forwarding and all initializer slots."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier

MANIFEST = None


class Phase7MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.path = next(iter(cls.manifest['destinations']))

    def verify(self, current, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current)
        self.assertEqual(2417, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-7 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason):
        current = dict(self.current)
        text = self.manifest['added'][0]['text'] if path == self.manifest['source'] else current[path]
        self.assertEqual(1, text.count(before))
        self.assertEqual(1, current[path].count(text))
        current[path] = current[path].replace(text, text.replace(before, after))
        self.verify(current, reason)

    def test_complete_production_extraction_all_16_proofs(self):
        self.verify(self.current)
        self.assertEqual(30, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(16, len(self.manifest['initializer_timing']))
        self.assertEqual(8, len(self.manifest['overload_audit']))
        self.assertEqual(1, len(self.manifest['added']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase7')
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_contiguous_field_still_requires_inert_proof(self):
        m = copy.deepcopy(self.manifest)
        m['initializer_timing'] = [r for r in m['initializer_timing']
                                  if not r['original'].endswith('/property stremioTvGuideOverlay')]
        self.verify(self.current, 'initializer timing coverage differs', m)

    def test_wait_listener_requires_its_inert_proof(self):
        m = copy.deepcopy(self.manifest)
        m['initializer_timing'] = [r for r in m['initializer_timing']
                                  if not r['original'].endswith('/property guidePanelReadyListener')]
        self.verify(self.current, 'initializer timing coverage differs', m)

    def test_playback_forwarder_cannot_drop_hide_guide_argument(self):
        self.edit(self.manifest['source'],
            '.playStremioTvPlaybackMap(channel, map, url, title, hideGuideOnReady)',
            '.playStremioTvPlaybackMap(channel, map, url, title)', 'added declaration:')

    def test_playback_forwarder_cannot_hardcode_hide_guide_argument(self):
        self.edit(self.manifest['source'],
            '.playStremioTvPlaybackMap(channel, map, url, title, hideGuideOnReady)',
            '.playStremioTvPlaybackMap(channel, map, url, title, false)', 'added declaration:')

    def test_playback_host_signature_cannot_drop_hide_guide_argument(self):
        self.edit(self.path,
            'fun playStremioTvPlaybackMap(channel: StremioTvGuideChannel, map: Map<*, *>, url: String, title: String, hideGuideOnReady: Boolean)',
            'fun playStremioTvPlaybackMap(channel: StremioTvGuideChannel, map: Map<*, *>, url: String, title: String)',
            'pinned destination:')

    def test_player_forwarder_cannot_snapshot(self):
        self.edit(self.manifest['source'],
            'override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player',
            'override val player: ExoPlayer? = this@AndroidTvTorrentPlayerActivity.player',
            'added declaration:')

    def test_mode_setter_must_remain_explicitly_qualified(self):
        self.edit(self.manifest['source'],
            'set(value) { this@AndroidTvTorrentPlayerActivity.isStremioTvMode = value }',
            'set(value) { isStremioTvMode = value }', 'added declaration:')

    def test_finish_must_dispatch_to_activity_override(self):
        current = dict(self.current)
        self.assertEqual(6, current[self.path].count('activity.finish()'))
        current[self.path] = current[self.path].replace('activity.finish()', 'host.finish()')
        self.verify(current, 'token mismatch:')

    def test_next_cannot_start_guide_wait(self):
        self.edit(self.path, 'hideGuideOnReady = false', 'hideGuideOnReady = true', 'token mismatch:')

    def test_next_default_argument_cannot_change(self):
        self.edit(self.path, 'finishOnFailure: Boolean = false',
                  'finishOnFailure: Boolean = true', 'token mismatch:')

    def test_guide_data_cannot_gain_switch_token_guard(self):
        self.edit(self.path, 'val data = result as? Map<*, *>\n',
                  'if (stremioTvSwitchToken != 0) return\n                        val data = result as? Map<*, *>\n',
                  'token mismatch:')

    def test_player_view_find_must_keep_its_receiver(self):
        self.edit(self.path, 'host.playerView.findViewById(R.id.debrify_playlist_button)',
                  'activity.findViewById(R.id.debrify_playlist_button)', 'token mismatch:')

    def test_controller_property_cannot_move_from_first_field_slot(self):
        current = dict(self.current)
        row = self.manifest['added'][0]
        source = current[self.manifest['source']].replace(row['text'], '')
        marker = '    private var isStremioTvMode = false'
        self.assertEqual(1, source.count(marker))
        current[self.manifest['source']] = source.replace(marker, row['text'] + '\n' + marker)
        self.verify(current, 'retained declaration order changed:')

    def test_all_33_earlier_destinations_frozen(self):
        current = {p: (k.ROOT / p).read_text() for p in self.manifest['earlier_destinations']['paths']}
        self.assertEqual(33, len(current))
        self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        path = next(p for p in current if Path(p).stem == 'TvIptvZapBannerStyledRenderer')
        current[path] += '\nfun unreviewed() = 1\n'
        self.assertIn('earlier destination changed beyond reviewed whitelist: ' + path,
                      check_earlier(self.manifest, k.ROOT, current))

    def test_historical_phase6_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'),
            '--manifest', str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p6.json'), '--at', 'a4ed4f368'],
            capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
