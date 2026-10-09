"""Offline compiled retained-binding casts/stores, fields and volatile negatives."""
from pathlib import Path
import copy
import unittest

import check_kotlin_moves as k
from test_kotlin_overloads_phase15 import Phase15OverloadsTest
from kotlin_overloads_phase16 import audit_binding_site, field_declarations, audit_identity


class Phase16OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=k.evidence_root(k.ROOT)/(k.EVIDENCE_PHASE+'/overload-selftests-phase16')
        cls.source=(k.ROOT/'dev/tool/fixtures/kotlin_overloads/phase16.kt').read_text()
        cls.good=cls.compile('original',cls.source)
        cls.fields=field_declarations(cls.folder/'original/audit-classes')
        cls.identity_pin=dict(descriptor='Ljava/lang/String;',writers=['handleMetadataUpdate','replacePayloadWithStremioTvItem'],reader='playlistController')
        cls.before_fields={('com.debrify.app.tv.AndroidTvTorrentPlayerActivity','ottShowName'):dict(descriptor='Ljava/lang/String;',volatile=True)}
        cls.pins=[]
        for field,target,cast,descriptor in [('pauseButton','pauseButton','androidx/appcompat/widget/AppCompatButton','Landroidx/appcompat/widget/AppCompatButton;'),('ottQualityChips','ottQualityChips[0]',None,'[Landroid/widget/TextView;'),('controlsOverlay','controlsOverlay',None,'Landroid/view/View;')]:
            line=next(i+1 for i,s in enumerate(cls.source.splitlines()) if 'host.'+target+' =' in s)
            cls.pins.append(dict(field=field,assignment_target=target,cast=cast,descriptor=descriptor,context=cls.source.splitlines()[line-1],line=line))

    @classmethod
    def compile(cls,label,source):
        return Phase15OverloadsTest.compile.__func__(cls,label,source)

    def test_compiled_retained_cast_no_cast_array_stores(self):
        for pin in self.pins:self.assertEqual(2,len(audit_binding_site(pin,pin['line'],self.good,self.good)))

    def test_compiled_lost_cast_from_widening(self):
        source=self.source.replace('var pauseButton: AppCompatButton?','var pauseButton: View?')
        bad=self.compile('widened',source);pin=self.pins[0]
        with self.assertRaisesRegex(ValueError,'cast presence/type differs'):audit_binding_site(pin,pin['line'],self.good,bad)

    def test_compiled_added_cast_on_array(self):
        source=self.source.replace('playerView.findViewById(2)','playerView.findViewById<View>(2) as? TextView')
        bad=self.compile('array-cast',source);pin=self.pins[1]
        with self.assertRaisesRegex(ValueError,'cast presence/type differs'):audit_binding_site(pin,pin['line'],self.good,bad)

    def test_compiled_wrong_descriptor_without_cast(self):
        source=self.source.replace('Array<TextView?>','Array<View?>')
        bad=self.compile('array-type',source);pin=self.pins[1]
        with self.assertRaisesRegex(ValueError,'Host descriptor/array store differs'):audit_binding_site(pin,pin['line'],self.good,bad)

    def test_compiled_missing_array_store(self):
        source=self.source.replace('host.ottQualityChips[0] = playerView.findViewById(2)','host.ottQualityChips; playerView.findViewById<View>(2)')
        bad=self.compile('array-store',source);pin=self.pins[1]
        with self.assertRaisesRegex(ValueError,'Host descriptor/array store differs'):audit_binding_site(pin,pin['line'],self.good,bad)

    def test_compiled_original_volatile_field_descriptor(self):
        self.assertEqual(dict(descriptor='Ljava/lang/String;',volatile=True),self.fields['com.debrify.app.tv.TvDockIdentityPresenter','ottShowName'])

    def test_compiled_removed_volatile_annotation(self):
        self.compile('no-volatile',self.source.replace('@Volatile ',''))
        bad=field_declarations(self.folder/'no-volatile/audit-classes')
        with self.assertRaisesRegex(ValueError,'ACC_VOLATILE and descriptor'):
            audit_identity(self.identity_pin,self.before_fields,bad,self.good)

    def test_compiled_widened_identity_field_descriptor(self):
        self.compile('identity-type',self.source.replace('var ottShowName: String?','var ottShowName: Any?'))
        bad=field_declarations(self.folder/'identity-type/audit-classes')
        with self.assertRaisesRegex(ValueError,'ACC_VOLATILE and descriptor'):
            audit_identity(self.identity_pin,self.before_fields,bad,self.good)

    def test_compiled_identity_writers_and_playlist_read(self):
        audit_identity(self.identity_pin,self.before_fields,self.fields,self.good)

    def test_compiled_identity_writer_dropped(self):
        bad=self.compile('writer-dropped',self.source.replace('fun handleMetadataUpdate(name: String?) { identity.ottShowName = name }','fun handleMetadataUpdate(name: String?) {}'))
        with self.assertRaisesRegex(ValueError,'writer dispatch differs'):
            audit_identity(self.identity_pin,self.before_fields,self.fields,bad)

    def test_compiled_identity_playlist_reader_dropped(self):
        bad=self.compile('reader-dropped',self.source.replace('fun name() = identity.ottShowName','fun name(): String? = null'))
        with self.assertRaisesRegex(ValueError,'playlist Host read dispatch differs'):
            audit_identity(self.identity_pin,self.before_fields,self.fields,bad)
