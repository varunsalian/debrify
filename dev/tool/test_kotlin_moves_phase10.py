"""Phase-10 production extraction, live forwarding, lifecycle and receiver negatives."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier

MANIFEST = None


class Phase10MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.count = len(list(k.walk(k.parse({'base': cls.original})['base']['declarations'])))
        cls.path = next(iter(cls.manifest['destinations']))
        cls.source = cls.manifest['source']

    def verify(self, current, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current)
        self.assertEqual(self.count, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-10 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def host_edit(self, before, after):
        current = dict(self.current); row = self.manifest['added'][0]
        self.assertEqual(1, row['text'].count(before))
        current[self.source] = current[self.source].replace(row['text'], row['text'].replace(before, after))
        self.verify(current, 'added declaration:')

    def test_complete_production_extraction_all_four_proofs(self):
        self.verify(self.current)
        self.assertEqual(29, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(4, len(self.manifest['initializer_timing']))
        self.assertEqual(32, len(self.manifest['overload_audit']))
        self.assertEqual(4, len(self.manifest['runnable_receivers']))
        self.assertEqual(5, len(self.manifest['added']))
        for name, edits in [('subtitleController', 3), ('sourceSwitchController', 12), ('startupGateController', 5)]:
            row = next(r for r in self.manifest['declarations'] if r['original'].endswith('/property ' + name))
            self.assertEqual('patched', row['fate']); self.assertEqual(edits, sum(e['count'] for e in row['patches']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase10')
        for path, text in self.current.items():
            target = folder / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)

    def path_for(self, name):
        return next(p for p in self.current if Path(p).stem == name)

    def change_added(self, name, before, after):
        current = dict(self.current); row = next(r for r in self.manifest['added'] if r['target'].endswith('/property ' + name))
        self.assertEqual(1, row['text'].count(before))
        current[self.source] = current[self.source].replace(row['text'], row['text'].replace(before, after))
        self.verify(current, 'added declaration:')

    def test_retry_id_forwarder_cannot_snapshot(self):
        self.edit(self.source, 'override val pikPakRetryId: Int get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.pikPakRetryId',
                  'override val pikPakRetryId: Int = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.pikPakRetryId', 'token mismatch:')

    def test_episode_lock_forwarder_cannot_snapshot(self):
        self.change_added('sourceFetchController', 'override var stremioResolutionToken: Int\n                get() =', 'override val stremioResolutionToken: Int =')

    def test_player_forwarder_cannot_snapshot(self):
        self.change_added('pikPakRetryController', 'override val player: ExoPlayer? get() =', 'override val player: ExoPlayer? =')

    def test_live_episode_read_cannot_snapshot(self):
        self.edit(self.source, 'if (sourceFetchController.episodeFetchInFlight)', 'if (false)', 'token mismatch:', 2)

    def extra_property_edit(self, name):
        current = dict(self.current); unit = k.parse({'s': current[self.source]})['s']
        node = next(n for n in k.walk(unit['declarations']) if n['id'].endswith('/property ' + name))
        start = current[self.source].index('this@AndroidTvTorrentPlayerActivity.', node['start'], node['end'])
        current[self.source] = current[self.source][:start] + 'this@OtherActivity.' + current[self.source][start+len('this@AndroidTvTorrentPlayerActivity.'):]
        self.verify(current, 'token mismatch:')

    def test_subtitle_extra_edit(self): self.extra_property_edit('subtitleController')
    def test_switcher_extra_edit(self): self.extra_property_edit('sourceSwitchController')
    def test_gate_extra_edit(self): self.extra_property_edit('startupGateController')

    def test_missed_subtitle_repoint(self):
        self.edit(self.source, 'this@AndroidTvTorrentPlayerActivity.statusPillController.showStatusPill(message)',
                  'this@AndroidTvTorrentPlayerActivity.showStatusPill(message)', 'token mismatch:')

    def test_missed_gate_qualification(self):
        self.edit(self.path_for('TvPikPakRetryController'), 'host.startupGateController.', 'startupGateController.', 'token mismatch:', 8)

    def test_missed_switcher_qualification(self):
        self.edit(self.path_for('TvSourceFetchController'), 'host.sourceSwitchController.', 'sourceSwitchController.', 'token mismatch:', 4)

    def test_prefix_increment_cannot_be_read_then_write(self):
        self.edit(self.path_for('TvSourceFetchController'), 'val token = ++host.stremioResolutionToken',
                  'val token = host.stremioResolutionToken\n        host.stremioResolutionToken = token + 1', 'token mismatch:', 2)

    def omit_proof(self, name):
        m = copy.deepcopy(self.manifest); m['initializer_timing'] = [r for r in m['initializer_timing'] if not r['original'].endswith('/property ' + name)]
        self.verify(self.current, 'initializer timing coverage differs', m)
    def test_pill_runnable_proof_required(self): self.omit_proof('statusPillHideRunnable')
    def test_retry_handler_proof_required(self): self.omit_proof('pikPakRetryHandler')

    def test_host_same_name_capture(self):
        current = dict(self.current); path = self.path_for('TvSourceFetchController')
        current[path] = current[path].replace('    interface Host {', '    interface Host {\n        fun adoptSourceList(map: Map<*, *>?) {}')
        current[path] = current[path].replace('        adoptSourceList(map)', '        host.adoptSourceList(map)')
        self.verify(current, 'pinned destination:'); self.verify(current, 'token mismatch:')

    def test_unbraced_host_template(self):
        self.edit(self.path_for('TvSourceFetchController'), '${host.stremioSources.size}', '$host.stremioSources.size', 'token mismatch:')

    def test_guide_parameter_cannot_be_renamed(self):
        self.change_added('sourceFetchController', 'allowResolverFallback: Boolean', 'resolverFallback: Boolean')

    def test_guide_parameter_cannot_have_default(self):
        self.edit(self.path_for('TvSourceFetchController'), 'allowResolverFallback: Boolean): SeasonEpisode?',
                  'allowResolverFallback: Boolean = false): SeasonEpisode?', 'pinned destination:')

    def test_constructor_receiver_cannot_be_widened(self):
        self.edit(self.path_for('TvStatusPillController'), 'TextView(activity)', 'TextView(activity.applicationContext)', 'token mismatch:')

    def test_find_view_must_not_route_through_host(self):
        self.edit(self.path_for('TvStatusPillController'), 'activity.findViewById', 'host.findViewById', 'token mismatch:')

    def test_on_destroy_two_pk_statements_cannot_be_reordered(self):
        self.edit(self.source, 'pikPakRetryController.cancelPikPakRetry()\n        pikPakRetryController.pikPakRetryHandler.removeCallbacksAndMessages(null)',
                  'pikPakRetryController.pikPakRetryHandler.removeCallbacksAndMessages(null)\n        pikPakRetryController.cancelPikPakRetry()', 'token mismatch:')

    def test_on_destroy_cleanup_cannot_be_folded(self):
        self.edit(self.source, 'pikPakRetryController.cancelPikPakRetry()\n        pikPakRetryController.pikPakRetryHandler.removeCallbacksAndMessages(null)', 'pikPakRetryController.destroy()', 'token mismatch:')

    def test_on_pause_cancellation_cannot_be_reordered(self):
        self.edit(self.source, 'ActivityTracker.currentActivity = null\n        }\n        // Cancel any ongoing PikPak retry operations\n        pikPakRetryController.cancelPikPakRetry()',
                  'ActivityTracker.currentActivity = null\n            pikPakRetryController.cancelPikPakRetry()\n        }', 'token mismatch:')

    def test_readiness_stays_activity_owned(self):
        self.change_added('startupGateStatusReady', '::startupGateStatus.isInitialized', 'true')

    def test_earlier_37_destinations_frozen(self):
        current = {p: (k.ROOT / p).read_text() for p in self.manifest['earlier_destinations']['paths']}
        self.assertEqual(37, len(current)); self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        for path in [p for p in current if Path(p).stem in {'TvSubtitleController', 'TvStartupGateController', 'TvSourceSwitchController', 'TvSourceSwitchApplier'}]:
            changed = dict(current); changed[path] += '\nfun unreviewed() = 1\n'
            self.assertIn('earlier destination changed beyond reviewed whitelist: ' + path, check_earlier(self.manifest, k.ROOT, changed))

    def test_historical_phase9_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'), '--manifest',
            str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p9.json'), '--at', '8a4d40d1c'], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
