"""Keep IPTV's exact clock seam pinned through the timeline's declared moves."""
import json
from unittest.mock import patch
from check_verbatim_moves import ROOT,parse
from check_settings_moves import all_nodes,check_seams
from iptv_spotlight_timeline_checker_fixtures import SOURCE,STATE,inputs,layout
from iptv_spotlight_timeline_source_reader import validate


def self_test(package):
 original,rows,config,parsed,leaves=inputs(package)
 consumer=json.loads((ROOT/'dev/tool/iptv_checker_config.json').read_text())
 spec=next(s for s in consumer['seams'] if s['file']==SOURCE)
 assert spec['source_reader_module']=='iptv_spotlight_timeline_source_reader'
 only={**consumer,'seams':[spec]}
 for step in range(4):
  cfg={**config,'completed_step':step}
  sources=layout(original,rows,cfg,parsed,leaves,step)
  def read(path,unused):
   assert path==SOURCE
   return validate(original,sources,rows,cfg,package)['source']
  with patch('iptv_spotlight_timeline_source_reader.read_validated_source',side_effect=read):
   _,errors=check_seams('',{},only,consumer['baseline'],package)
   assert not errors,errors
   print('IPTV auxiliary clock seam S='+str(step)+': PASS',flush=True)
   identity=STATE+'._dayHeading'
   row=next(r for r in rows if r['original_name']==identity)
   path=row['destination_file'] if step>=int(row['step']) else SOURCE
   owner=row['destination_class'] if step>=int(row['step']) else STATE
   name=row['new_name'] if step>=int(row['step']) else '_dayHeading'
   node=all_nodes(parse(sources,package))[(path,owner,name)]
   before='final now = widget.now();'
   assert node['text'].count(before)==1
   body=node['text'].replace(before,'final now = DateTime.now();',1)
   sources[path]=sources[path][:node['start']]+body+sources[path][node['end']:]
   _,errors=check_seams('',{},only,consumer['baseline'],package)
   assert any('Auxiliary clock seam changed outside its exact edits: '+SOURCE in e for e in errors),errors
   print('IPTV auxiliary moved clock mutation S='+str(step)+': rejected',flush=True)
  # Even a separately validated but different baseline cannot bypass the
  # consumer's original patched whole-file fingerprint.
  with patch('iptv_spotlight_timeline_source_reader.read_validated_source',return_value=original.replace('DateTime.now','DateTime.utc',1)):
   _,errors=check_seams('',{},only,consumer['baseline'],package)
   assert errors==['Auxiliary clock seam changed outside its exact edits: '+SOURCE],errors
   print('IPTV auxiliary baseline drift S='+str(step)+': rejected',flush=True)
 try:
  from iptv_spotlight_timeline_source_reader import read_validated_source
  read_validated_source('lib/unregistered.dart',package)
 except ValueError as error:assert 'Unregistered auxiliary timeline source' in str(error)
 else:raise AssertionError('auxiliary reader accepted an unregistered path')
 print('IPTV auxiliary reader unregistered path: rejected',flush=True)
