"""Compiled cast/absence, typed Host descriptors and Java constant-inlining guards."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_toolchain import kotlin_jars
from check_kotlin_overloads import typed_bytecode, audit_view_bindings, audit_constant_inlining


class Phase15OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=k.evidence_root(k.ROOT)/(k.EVIDENCE_PHASE+'/overload-selftests-phase15')
        cls.original=(k.ROOT/'dev/tool/fixtures/kotlin_overloads/phase15.kt').read_text()
        prefix=cls.original.split('class AndroidTvTorrentPlayerActivity')[0]
        cls.controller=prefix+'''internal class FixtureController(private val host: Host) {
    interface Host {
        var pauseButton: AppCompatButton?
        val ottQualityChips: Array<TextView?>
        var controlsOverlay: View?
    }
    private val playerView = PlayerView()
    private val resizeModes = arrayOf(AspectRatioFrameLayout.RESIZE_MODE_FIT, AspectRatioFrameLayout.RESIZE_MODE_FILL, AspectRatioFrameLayout.RESIZE_MODE_ZOOM)
    fun bind() {
        host.pauseButton = playerView.findViewById(1)
        host.ottQualityChips[0] = playerView.findViewById(2)
        host.controlsOverlay = playerView.findViewById(3)
    }
}
'''
        cls.before=cls.compile('original',cls.original)
        cls.after=cls.compile('controller',cls.controller)
        unit=k.parse({'original':cls.original})['original'];nodes={n['id']:n for n in k.walk(unit['declarations'])}
        bind=next(n for n in nodes.values() if n['selector']=='fun bind()');array=next(n for n in nodes.values() if n['selector']=='property resizeModes')
        cls.manifest=dict(phase=15,declarations=[dict(original=n['id'],fate='moved',destination='Controller.kt',target='class FixtureController/'+n['selector']) for n in (bind,array)],find_view_assignments=[],constant_inlining=[])
        types={'pauseButton':('AppCompatButton?','androidx/appcompat/widget/AppCompatButton','Landroidx/appcompat/widget/AppCompatButton;'),'ottQualityChips':('Array<TextView?>',None,'[Landroid/widget/TextView;'),'controlsOverlay':('View?',None,'Landroid/view/View;')}
        for site in unit['find_view_assignments']:
            field=site['target'].split('[',1)[0];typ,cast,descriptor=types[field];line=cls.original.count('\n',0,site['start'])+1
            cls.manifest['find_view_assignments'].append(dict(original=bind['id'],destination='Controller.kt',target='class FixtureController/fun bind()',line=line,context=cls.original.splitlines()[line-1].strip(),field=field,assignment_target=site['target'],source_type=typ,cast=cast,descriptor=descriptor,reason='Compiled cast and no-cast fixture.'))
        cls.manifest['constant_inlining']=[dict(original=array['id'],destination='Controller.kt',target='class FixtureController/property resizeModes',expression=array['initializer_text'],owner='androidx/media3/ui/AspectRatioFrameLayout',reason='Reviewed Java compile-time constants.')]
        (cls.folder/'manifest.json').write_text(json.dumps(cls.manifest,indent=2)+'\n')

    @classmethod
    def compile(cls,label,source,inline=True):
        folder=cls.folder/label;folder.mkdir(parents=True,exist_ok=True);target=folder/'classes';target.mkdir(exist_ok=True)
        java=folder/'AspectRatioFrameLayout.java';java.write_text('package androidx.media3.ui; public class AspectRatioFrameLayout { public static final int RESIZE_MODE_FIT = '+('0' if inline else 'Integer.parseInt("0")')+'; public static final int RESIZE_MODE_FILL = 1; public static final int RESIZE_MODE_ZOOM = 2; }')
        subprocess.run([str(k.JBR/'bin/javac'),'-d',str(target),str(java)],check=True,capture_output=True)
        sources={'Fixture.kt':source,'View.kt':'package android.view\nopen class View { fun <T: View> findViewById(id: Int): T? = null }\n','Widgets.kt':'package android.widget\nopen class TextView: android.view.View()\n','Button.kt':'package androidx.appcompat.widget\nclass AppCompatButton: android.widget.TextView()\n','Compat.kt':'package androidx.appcompat.app\nopen class AppCompatActivity\n','Player.kt':'package androidx.media3.ui\nclass PlayerView: android.view.View()\n'}
        paths=[]
        for name,text in sources.items():p=folder/name;p.write_text(text);paths.append(str(p))
        jars = kotlin_jars()
        result=subprocess.run([str(k.JBR/'bin/java'),'-cp',':'.join(map(str,jars)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',str(target)+':'+':'.join(map(str,jars)),'-d',str(target),*paths],capture_output=True,text=True)
        (folder/'compile.log').write_text(result.stdout+result.stderr);assert result.returncode==0,result.stdout+result.stderr
        flat=folder/'audit-classes';flat.mkdir(exist_ok=True)
        import shutil
        for p in (target/'com/debrify/app/tv').glob('*.class'):shutil.copy2(p,flat/p.name)
        return typed_bytecode(flat)

    def views(self,manifest=None,source=None,after=None):
        return audit_view_bindings(manifest or self.manifest,self.original,{'Controller.kt':source or self.controller},self.before,after or self.after)

    def test_compiled_cast_absence_and_descriptors(self):
        self.assertEqual(3,len(self.views()))
        self.assertEqual(1,len(audit_constant_inlining(self.manifest,self.original,self.before,self.after)))

    def test_every_assignment_required(self):
        for row in self.manifest['find_view_assignments']:
            m=copy.deepcopy(self.manifest);m['find_view_assignments'].remove(row)
            with self.assertRaisesRegex(ValueError,'audit coverage differs'):self.views(manifest=m)

    def test_cast_omitted_pin(self):
        m=copy.deepcopy(self.manifest);m['find_view_assignments'][0]['cast']=None
        with self.assertRaisesRegex(ValueError,'cast presence/type differs'):self.views(manifest=m)

    def test_cast_invented_for_view_or_array(self):
        for index in (1,2):
            m=copy.deepcopy(self.manifest);m['find_view_assignments'][index]['cast']='android/widget/TextView'
            with self.assertRaisesRegex(ValueError,'cast presence/type differs'):self.views(manifest=m)

    def test_descriptor_widened(self):
        m=copy.deepcopy(self.manifest);m['find_view_assignments'][0]['descriptor']='Landroid/view/View;'
        with self.assertRaisesRegex(ValueError,'field/Host descriptor differs'):self.views(manifest=m)

    def test_compiled_widened_host(self):
        source=self.controller.replace('var pauseButton: AppCompatButton?','var pauseButton: View?');after=self.compile('widened-host',source)
        with self.assertRaisesRegex(ValueError,'Host target type/nullability differs'):self.views(source=source,after=after)

    def test_compiled_added_array_cast(self):
        source=self.controller.replace('host.ottQualityChips[0] = playerView.findViewById(2)','host.ottQualityChips[0] = playerView.findViewById<View>(2) as? TextView');after=self.compile('added-array-cast',source)
        with self.assertRaisesRegex(ValueError,'cast presence/type differs'):self.views(source=source,after=after)

    def test_constructor_non_inlined_constant(self):
        after=self.compile('non-inline-constant',self.controller,inline=False)
        with self.assertRaisesRegex(ValueError,'must be inlined'):audit_constant_inlining(self.manifest,self.original,self.before,after)

    def test_constant_proof_omitted(self):
        m=copy.deepcopy(self.manifest);m['constant_inlining']=[]
        with self.assertRaisesRegex(ValueError,'proof coverage differs'):audit_constant_inlining(m,self.original,self.before,self.after)
