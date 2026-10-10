"""Offline compiled implicit outer dispatch, lazy allocation and volatile negatives."""
from pathlib import Path
import shutil
import subprocess
import unittest

import check_kotlin_moves as k
from check_kotlin_overloads import bytecode, typed_bytecode, resolve_inherited
from kotlin_overloads_phase16 import field_declarations
from kotlin_overloads_phase17 import audit_deferred, audit_borrowed, audit_host_setters, audit_reflected_lazy_getter


class Phase17OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=k.evidence_root(k.ROOT)/(k.EVIDENCE_PHASE+'/overload-selftests-phase17')
        cls.source=(k.ROOT/'dev/tool/fixtures/kotlin_overloads/phase17.kt').read_text()
        cls.compile('original',cls.source)
        cls.good=typed_bytecode(cls.folder/'original/audit-classes')
        cls.calls=bytecode(cls.folder/'original/audit-classes')
        cls.pins=[dict(name=n,descriptor=d) for n,d in [('currentIptvHttpHeaders','Ljava/util/Map;'),('iptvStrictTsActive','Z')]]

    @classmethod
    def compile(cls,label,source):
        folder=cls.folder/label;folder.mkdir(parents=True,exist_ok=True)
        sources={'Fixture.kt':source,'Context.kt':'package android.content\nopen class Context\n',
                 'View.kt':'package android.view\nopen class View\nopen class ViewGroup: View() { class LayoutParams }\n',
                 'Widget.kt':'package android.widget\nclass TextView(context: android.content.Context): android.view.View() { '+('fun addContentView(view: android.view.View, params: android.view.ViewGroup.LayoutParams) {}' if label=='inner' else '')+' }\n',
                 'Activity.kt':'package android.app\nopen class Activity: android.content.Context() { open fun addContentView(view: android.view.View, params: android.view.ViewGroup.LayoutParams) {} }\n',
                 'Compat.kt':'package androidx.appcompat.app\nopen class AppCompatActivity: android.app.Activity() { override fun addContentView(view: android.view.View, params: android.view.ViewGroup.LayoutParams) {} }\n'}
        paths=[]
        for name,text in sources.items():
            p=folder/name;p.write_text(text);paths.append(str(p))
        cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
        jars=[next((cache/g/a/v).glob('*/*.jar')) for g,a,v in [('org.jetbrains.kotlin','kotlin-compiler-embeddable','2.2.20'),('org.jetbrains.kotlin','kotlin-stdlib','2.2.20'),('org.jetbrains.kotlin','kotlin-reflect','2.2.0'),('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.8.0'),('org.jetbrains','annotations','13.0')]]
        target=folder/'classes'
        result=subprocess.run([str(k.JBR/'bin/java'),'-cp',':'.join(map(str,jars)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',':'.join(map(str,jars)),'-d',str(target),*paths],capture_output=True,text=True)
        (folder/'compile.log').write_text(result.stdout+result.stderr)
        assert result.returncode==0,result.stdout+result.stderr
        flat=folder/'audit-classes';flat.mkdir(exist_ok=True)
        for p in (target/'com/debrify/app/tv').glob('*.class'):shutil.copy2(p,flat/p.name)
        return typed_bytecode(flat)

    def dispatch(self,calls,owner,line,expected_owner):
        scope=[i for i in calls if i['owner']==owner]
        pin,_=resolve_inherited(scope,dict(callee='addContentView'),line,line)
        self.assertEqual(dict(owner=expected_owner,descriptor='(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V',opcode='invokevirtual'),pin)

    def test_compiled_outer_add_content_view_dispatch(self):
        original=next(i+1 for i,s in enumerate(self.source.splitlines()) if 'TextView(this).apply' in s)
        moved=next(i+1 for i,s in enumerate(self.source.splitlines()) if 'TextView(activity).apply' in s)
        self.dispatch(self.calls,'com.debrify.app.tv.AndroidTvTorrentPlayerActivity',original,'com/debrify/app/tv/AndroidTvTorrentPlayerActivity')
        self.dispatch(self.calls,'com.debrify.app.tv.TvIptvTuneController',moved,'androidx/appcompat/app/AppCompatActivity')

    def test_compiled_activity_widening_loses_override_owner(self):
        self.compile('wide',self.source.replace('private val activity: AppCompatActivity','private val activity: android.app.Activity'))
        calls=bytecode(self.folder/'wide/audit-classes')
        line=next(i+1 for i,s in enumerate(self.source.splitlines()) if 'TextView(activity).apply' in s)
        with self.assertRaises(AssertionError):self.dispatch(calls,'com.debrify.app.tv.TvIptvTuneController',line,'androidx/appcompat/app/AppCompatActivity')

    def test_compiled_inner_textview_capture_loses_outer_dispatch(self):
        self.compile('inner',self.source.replace('activity.addContentView(this','this.addContentView(this'))
        calls=bytecode(self.folder/'inner/audit-classes')
        line=next(i+1 for i,s in enumerate(self.source.splitlines()) if 'TextView(activity).apply' in s)
        with self.assertRaises(AssertionError):self.dispatch(calls,'com.debrify.app.tv.TvIptvTuneController',line,'androidx/appcompat/app/AppCompatActivity')

    def test_compiled_lazies_allocate_without_evaluation(self):
        audit_deferred(self.good)

    def test_compiled_eager_recovery_and_device_quirk_rejected(self):
        for name,before,after in [('recovery','by lazy { IptvLiveRecovery() }','= IptvLiveRecovery()'),('quirk','by lazy { IptvDeviceQuirks.startsIptvWithStrictTs() }','= IptvDeviceQuirks.startsIptvWithStrictTs()')]:
            bad=self.compile(name,self.source.replace(before,after))
            with self.assertRaisesRegex(ValueError,'eagerly evaluated'):audit_deferred(bad)

    def test_compiled_borrowed_activity_volatile_storage(self):
        audit_borrowed(self.pins,field_declarations(self.folder/'original/audit-classes'),self.good)

    def test_compiled_volatile_removal_rejected(self):
        bad=self.compile('no-volatile',self.source.replace('@Volatile ',''))
        with self.assertRaisesRegex(ValueError,'ACC_VOLATILE and descriptor'):
            audit_borrowed(self.pins,field_declarations(self.folder/'no-volatile/audit-classes'),bad)

    def test_compiled_controller_snapshot_rejected(self):
        bad=self.compile('snapshot',self.source.replace('val iptvLiveRecovery by lazy','val currentIptvHttpHeaders: Map<String,String> = emptyMap()\n    val iptvLiveRecovery by lazy'))
        with self.assertRaisesRegex(ValueError,'cannot be snapshotted'):
            audit_borrowed(self.pins,field_declarations(self.folder/'snapshot/audit-classes'),bad)

    def test_compiled_host_accessors_reach_activity_volatile_fields(self):
        audit_host_setters(self.pins,self.good)

    def test_compiled_host_setter_dropped_rejected(self):
        bad=self.compile('no-host-write',self.source.replace('set(value) { this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders = value }','set(value) {}'))
        with self.assertRaisesRegex(ValueError,'Host set must dispatch'):
            audit_host_setters(self.pins,bad)

    def test_compiled_reflected_lazy_getter_unmangled(self):
        audit_reflected_lazy_getter(self.good)

    def test_compiled_reflected_lazy_getter_mangling_rejected(self):
        bad=self.compile('mangled',self.source.replace('val iptvLiveRecovery by lazy','internal val iptvLiveRecovery by lazy'))
        with self.assertRaisesRegex(ValueError,'unmangled getIptvLiveRecovery'):
            audit_reflected_lazy_getter(bad)
