"""Complete two-sibling pipeline/receiver extraction and boundary negatives."""
import copy
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier
from kotlin_overloads_phase19 import writer_owners

MANIFEST = None


class Phase19MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            MANIFEST['base'] + ':' + MANIFEST['source']], text=True)
        cls.current = extraction(MANIFEST, cls.original)
        cls.source = MANIFEST['source']

    def path(self, name):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == name)

    def verify(self, current=None, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current or self.current)
        self.assertEqual(1611, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-19 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(8, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual([], self.manifest['initializer_timing'])
        self.assertEqual(21, len(self.manifest['overload_audit']))
        self.assertEqual(10, sum(s.get('receiver') != 'implicit-inherited' for s in self.manifest['overload_audit']))
        self.assertEqual(61, len(self.manifest['earlier_destinations']['paths']))
        for path, text in self.current.items():
            target = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase19') / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_original_self_comparison(self):
        errors, count = k.check(k.retained_manifest(self.source, self.original), self.original,
                                {self.source: self.original})
        self.assertEqual(([], 1611), (errors, count))

    def test_two_independent_siblings(self):
        for name, other in [('TvMediaPipelineController', 'TvEpisodeMetadataReceiver'),
                            ('TvEpisodeMetadataReceiver', 'TvMediaPipelineController')]:
            self.assertNotIn(other, self.current[self.path(name)])
            self.edit(self.path(name), '    interface Host {',
                '    interface Host {\n        val sibling: ' + other, 'pinned destination:')

    def test_only_pipeline_has_optin(self):
        p = self.path('TvMediaPipelineController')
        self.edit(p, '@OptIn(UnstableApi::class)\n', '', 'pinned destination:')
        p = self.path('TvEpisodeMetadataReceiver')
        self.edit(p, 'internal class TvEpisodeMetadataReceiver',
            '@OptIn(UnstableApi::class)\ninternal class TvEpisodeMetadataReceiver', 'pinned destination:')

    def test_slot_fields_at_original_position(self):
        for added in self.manifest['added']:
            m = copy.deepcopy(self.manifest)
            next(a for a in m['added'] if a['target'] == added['target'])['slot'] = 'class AndroidTvTorrentPlayerActivity/property activeVodHeaders'
            self.verify(manifest=m, reason='added slot must be a removed original field')
        for name in ('TvMediaPipelineController', 'TvEpisodeMetadataReceiver'):
            m = copy.deepcopy(self.manifest)
            p = self.path(name)
            m['destinations'][p]['order']['class ' + name].reverse()
            self.verify(manifest=m, reason='destination declaration order changed')

    def test_construction_time_host_read(self):
        for name in ('TvMediaPipelineController', 'TvEpisodeMetadataReceiver'):
            p = self.path(name)
            header = self.manifest['destinations'][p]['pinned_spans']['class ' + name + ':header']
            self.edit(p, header, header + '\n    init { host.player }', 'unexpected new declaration:')

    def test_computed_volatile_host_not_snapshot(self):
        for name in ('activeVodHeaders', 'currentIptvHttpHeaders', 'iptvStrictTsActive'):
            before = next(line for line in self.current[self.source].splitlines()
                          if 'override val ' + name + ':' in line and ' get()' in line)
            self.edit(self.source, before, before.replace(' get()', ''), 'added declaration:',
                      self.current[self.source].count(before))

    def test_removed_volatile_annotation(self):
        for name in ('activeVodHeaders', 'currentIptvHttpHeaders', 'iptvStrictTsActive'):
            before = ('@Volatile\n    private var ' if name == 'currentIptvHttpHeaders' else '@Volatile private var ') + name
            self.edit(self.source, before, 'private var ' + name, 'retain @Volatile')

    def test_snapshot_resolver_read(self):
        p = self.path('TvMediaPipelineController')
        self.edit(p, 'val headers = host.currentIptvHttpHeaders', 'val headers = emptyMap<String, String>()', 'token mismatch:')

    def test_shadowed_intent_and_context_preserved(self):
        p = self.path('TvEpisodeMetadataReceiver')
        self.assertEqual(7, self.current[p].count('intent?.getStringExtra(') + self.current[p].count('                    intent,'))
        self.edit(p, 'intent?.getStringExtra(', 'activity.intent?.getStringExtra(', 'token mismatch:', 5)
        self.edit(p, 'context: android.content.Context?', 'context: AppCompatActivity?', 'token mismatch:')

    def test_identity_provider_key_remains_activity(self):
        p = self.path('TvMediaPipelineController')
        self.edit(p, 'setActiveSubtitleIdentityProvider(activity)',
            'setActiveSubtitleIdentityProvider(this@TvMediaPipelineController)', 'token mismatch:')

    def test_lazy_first_access_not_constructor(self):
        p = self.path('TvMediaPipelineController')
        for name in ('iptvRecordingController', 'iptvTuneController'):
            self.edit(p, '    interface Host {', '    private val snapshot = host.' + name + '\n    interface Host {',
                'unexpected new declaration:')

    def test_host_setter_and_reread_not_cached(self):
        before = 'get() = this@AndroidTvTorrentPlayerActivity.player'
        # Several old computed Hosts use the same substring. Replace the whole
        # newly added property, so this negative owns exactly one structural span.
        row = next(a for a in self.manifest['added'] if 'mediaPipelineController' in a['target'])
        self.edit(self.source, row['text'], row['text'].replace(before, 'get() = null', 1), 'added declaration:')

    def test_metadata_default_arguments_and_private_visibility(self):
        p = self.path('TvEpisodeMetadataReceiver')
        for before, after in [('guideJson: String? = null', 'guideJson: String? = ""'),
                              ('showName: String? = null', 'showName: String? = ""'),
                              ('private fun handleMetadataUpdate(', 'fun handleMetadataUpdate(')]:
            self.edit(p, before, after, 'token mismatch:')

    def test_register_then_request_order(self):
        p = self.path('TvEpisodeMetadataReceiver')
        before = '        requestMetadataFromFlutter()'
        self.edit(p, before, '        activity.registerReceiver(metadataUpdateReceiver, filter)\n' + before, 'token mismatch:')

    def test_consumed_patch_qualifications(self):
        for stem, fragment, count in [('TvEpisodeMetadataReceiver', 'host.controlsOverlayController.identity.', 4),
                                      ('TvEpisodeMetadataReceiver', 'host.playbackStartController.navigator.', 1),
                                      ('TvMediaPipelineController', 'host.iptvTuneController.', 3)]:
            self.edit(self.path(stem), fragment, fragment.removeprefix('host.'), 'token mismatch:', count)

    def test_deliberately_absent_host_members(self):
        p = self.path('TvMediaPipelineController')
        for name in ('setupPlayer', 'iptvMediaCodecSelector', 'iptvDiagAnalyticsListener'):
            self.edit(p, '    interface Host {', '    interface Host {\n        val ' + name + ': Any', 'pinned destination:')

    def test_inherited_networkcallback_outer_receiver(self):
        p = self.path('TvMediaPipelineController')
        self.edit(p, 'activity.runOnUiThread { host.iptvTuneController.iptvLiveRecovery.setOffline(false) }',
            'runOnUiThread { host.iptvTuneController.iptvLiveRecovery.setOffline(false) }', 'token mismatch:')

    def test_context_constant_qualification_and_value(self):
        p = self.path('TvMediaPipelineController')
        for name in ('ACTIVITY_SERVICE', 'CONNECTIVITY_SERVICE'):
            self.edit(p, 'Context.' + name, '"wrong"', 'token mismatch:')
        m = copy.deepcopy(self.manifest)
        m['constant_receivers'].pop()
        self.verify(manifest=m, reason='constant coverage differs')

    def test_whole_host_repoint_extra_edit(self):
        before = 'this@AndroidTvTorrentPlayerActivity.episodeMetadataReceiver.requestMetadataFromFlutter()'
        self.edit(self.source, before, 'this@AndroidTvTorrentPlayerActivity.episodeMetadataReceiver.setupMetadataReceiver()', 'token mismatch:')

    def test_teardown_stays_in_place(self):
        before = '        episodeMetadataReceiver.metadataUpdateReceiver = null'
        self.edit(self.source, before, '        episodeMetadataReceiver.teardown()', 'token mismatch:')
        current = dict(self.current)
        current[self.source] = current[self.source].replace(before, '').replace('        subtitleScope.cancel()', '        subtitleScope.cancel()\n' + before)
        self.verify(current, 'token mismatch:')

    def test_before_after_writer_owner_maps_required(self):
        self.assertEqual(writer_owners(), self.manifest['identity_writer_owners'])
        for direction in ('before', 'after'):
            m = copy.deepcopy(self.manifest)
            m['identity_writer_owners'][direction]['handleMetadataUpdate'] = 'com.debrify.app.tv.TvPlaybackStartController'
            self.verify(manifest=m, reason='writer owner-map coverage differs')

    def test_every_read_chain_and_current_historical_site_required(self):
        for group, reason in [('volatile_read_chains', 'read-chain descriptor/role coverage differs'),
                              ('overload_audit', 'audit coverage differs'),
                              ('retained_receiver_sites', 'historical receiver audit coverage differs'),
                              ('retained_view_bindings', 'retained phase-15 view-binding coverage')]:
            m = copy.deepcopy(self.manifest)
            m[group].pop()
            self.verify(manifest=m, reason=reason)

    def test_zero_initializer_proofs_no_unreviewed_additions(self):
        m = copy.deepcopy(self.manifest)
        m['initializer_timing'].append(dict(original='invalid', expression='anything', kind='constant', reason='invalid'))
        self.verify(manifest=m, reason='initializer')

    def test_frozen_previous_destinations_and_shuffle(self):
        self.assertEqual([], check_earlier(self.manifest, k.ROOT))
        m = copy.deepcopy(self.manifest)
        m['earlier_destinations']['paths'].pop()
        self.assertIn('earlier destination coverage differs', '\n'.join(check_earlier(m, k.ROOT)))
        m = copy.deepcopy(self.manifest)
        m['retained_source_bound_initializers'] = []
        self.verify(manifest=m, reason='ShowShuffle source-bound proof coverage differs')
