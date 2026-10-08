"""Phase-8 production fixture: source selection, eager applier and retained gate."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier

MANIFEST = None


class Phase8MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.count = 2335
        cls.path = next(p for p in cls.manifest['destinations'] if p.endswith('Controller.kt'))
        cls.applier = next(p for p in cls.manifest['destinations'] if p.endswith('Applier.kt'))

    def verify(self, current, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current)
        self.assertEqual(self.count, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-8 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify(self.current)
        self.assertEqual(15, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(1, len(self.manifest['initializer_timing']))
        self.assertEqual(1, len(self.manifest['overload_audit']))
        self.assertEqual(1, len(self.manifest['nested_construction']))
        self.assertEqual(1, len(self.manifest['added']))
        row = next(r for r in self.manifest['declarations'] if r['original'].endswith('/property iptvChannelStartController'))
        self.assertEqual('patched', row['fate'])
        self.assertEqual(4, sum(x['count'] for x in row['patches']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase8')
        for path, text in self.current.items():
            target = folder / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)

    def test_timeout_requires_inert_proof(self):
        m = copy.deepcopy(self.manifest); m['initializer_timing'] = []
        self.verify(self.current, 'initializer timing coverage differs', m)

    def test_applier_qualification_cannot_be_missed(self):
        self.edit(self.path, 'applier.switchToStremioSource(source.directUrl, source.index)',
                  'switchToStremioSource(source.directUrl, source.index)', 'token mismatch:')

    def test_switcher_qualification_cannot_be_missed(self):
        self.edit(self.applier, 'switcher.updateStremioQualityBadge()',
                  'updateStremioQualityBadge()', 'token mismatch:', 2)

    def test_same_name_host_cannot_capture_cross_call(self):
        current = dict(self.current)
        current[self.path] = current[self.path].replace('    interface Host {',
            '    interface Host {\n        fun updateStremioQualityBadge() {}')
        current[self.applier] = current[self.applier].replace('switcher.updateStremioQualityBadge()',
                                                            'host.updateStremioQualityBadge()')
        self.verify(current, 'token mismatch:')
        self.verify(current, 'pinned destination:')
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/host-capture')
        for path, text in current.items():
            target = folder / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)

    def test_retry_id_forwarder_cannot_snapshot(self):
        self.edit(self.manifest['source'],
            'override var pikPakRetryId: Int\n                get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryId',
            'override var pikPakRetryId: Int = this@AndroidTvTorrentPlayerActivity.pikPakRetryId', 'added declaration:')

    def test_player_forwarder_cannot_snapshot(self):
        # Other Hosts also read player; scope this edit to the exact added property.
        current = dict(self.current); row = self.manifest['added'][0]
        changed = row['text'].replace('override val player: ExoPlayer? get() =', 'override val player: ExoPlayer? =')
        current[self.manifest['source']] = current[self.manifest['source']].replace(row['text'], changed)
        self.verify(current, 'added declaration:')

    def test_play_item_forwarder_cannot_drop_argument(self):
        self.edit(self.manifest['source'],
            '.playItem(index, suppressTrakt, suppressResume, shuffleAttempt)',
            '.playItem(index, suppressTrakt, suppressResume)', 'added declaration:')

    def test_play_item_host_cannot_have_changed_default(self):
        self.edit(self.path, 'suppressTrakt: Boolean, suppressResume: Boolean, shuffleAttempt: ShufflePlaybackAttempt?',
                  'suppressTrakt: Boolean = false, suppressResume: Boolean, shuffleAttempt: ShufflePlaybackAttempt?',
                  'pinned destination:')

    def test_volatile_setter_must_write_original_field(self):
        self.edit(self.manifest['source'],
            'set(value) { this@AndroidTvTorrentPlayerActivity.activeVodHeaders = value }',
            'set(value) { cachedHeaders = value }', 'added declaration:')

    def test_original_volatile_annotation_cannot_be_removed(self):
        self.edit(self.manifest['source'], '@Volatile private var activeVodHeaders:',
                  'private var activeVodHeaders:', 'token mismatch:')

    def test_applier_must_be_eager(self):
        self.edit(self.path, 'internal val applier = TvSourceSwitchApplier(activity, host, this)',
                  'internal val applier by lazy { TvSourceSwitchApplier(activity, host, this) }', 'pinned destination:')

    def test_applier_cannot_read_host_during_construction(self):
        self.edit(self.applier, '    fun switchToSourcePlaylist(',
                  '    init { host.cancelPikPakRetry() }\n    private fun switchToSourcePlaylist(',
                  'unexpected new declaration:')

    def test_applier_initializer_position_pinned(self):
        current = dict(self.current); text = self.manifest['nested_construction'][0]['text']
        current[self.path] = current[self.path].replace(text, '')
        marker = '    private var sourceSwitchReadyListener: Player.Listener? = null'
        current[self.path] = current[self.path].replace(marker, marker + text)
        self.verify(current, 'destination declaration order changed:')

    def test_shuffle_visibility_patch_cannot_hide_extra_edit(self):
        self.edit(self.manifest['source'], 'var finished: Boolean = false,\n    )',
                  'var finished: Boolean = true,\n    )', 'token mismatch:')

    def test_iptv_whole_property_cannot_hide_extra_edit(self):
        current = dict(self.current); m = self.manifest
        row = next(r for r in m['declarations'] if r['original'].endswith('/property iptvChannelStartController'))
        unit = k.parse({'source': current[m['source']]})['source']
        node = next(n for n in k.walk(unit['declarations']) if n['id'] == row['original'])
        text = current[m['source']][node['start']:node['end']]
        self.assertIn('.watchSourceSwitchOutcome(sourceIndex)', text)
        current[m['source']] = current[m['source']][:node['start']] + text.replace(
            '.watchSourceSwitchOutcome(sourceIndex)', '.watchSourceSwitchOutcome(0)') + current[m['source']][node['end']:]
        self.verify(current, 'token mismatch:')

    def test_all_34_earlier_destinations_frozen(self):
        current = {p: (k.ROOT / p).read_text() for p in self.manifest['earlier_destinations']['paths']}
        self.assertEqual(34, len(current)); self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        path = next(p for p in current if Path(p).stem == 'TvStremioTvGuideController')
        current[path] += '\nfun unreviewed() = 1\n'
        self.assertIn('earlier destination changed beyond reviewed whitelist: ' + path,
                      check_earlier(self.manifest, k.ROOT, current))

    def test_historical_phase7_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'),
            '--manifest', str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p7.json'), '--at', '53906805d'],
            capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
