"""Catalog-only call receivers, live host reads, and State route subscription.

These checks run before ordinary move normalization. Other configs have no
catalog_* entries; no other manifest's accepted behavior is changed.
"""
from torbox_callback_identity import argument_ranges


def check_contracts(lookup, rows, source, config):
    from check_settings_moves import tokens
    errors=[]
    def node_for(member):
        row=next(r for r in rows if r['original_name']==member)
        key=(row['destination_file'],row['destination_class'],row['new_name'])
        if key in lookup:return lookup[key]
        owner,_,name=member.rpartition('.')
        return lookup[(source,owner,name)]
    for spec in config.get('catalog_call_receivers',[]):
        try:
            values=tokens(node_for(spec['member']))
            positions=[i for i,v in enumerate(values) if v==spec['call'] and values[i+1:i+2]==['(']]
            i=positions[spec.get('occurrence',0)]
            start=i-2
            while start>=2 and values[start-1]=='.':start-=2
            actual=''.join(values[start:i-1])
            if actual!=spec['receiver']:errors.append('Catalog call receiver differs: '+str(spec)+' actual '+actual)
        except (KeyError,IndexError,StopIteration):errors.append('Missing catalog receiver site: '+str(spec))
    for spec in config.get('catalog_live_reads',[]):
        try:
            values=tokens(node_for(spec['member']))
            direct=['widget','.',spec['getter']]
            getter=['_deps','.',spec['getter'],'(',')']
            count=sum(values[i:i+3]==direct or values[i:i+5]==getter for i in range(len(values)))
            if count!=spec['count']:errors.append('Catalog live host read changed at original evaluation site: '+str(spec))
        except (KeyError,StopIteration):errors.append('Missing catalog host site: '+str(spec))
    for spec in config.get('catalog_host_assignments',[]):
        try:
            values=tokens(node_for(spec['member']))
            start=next(i+3 for i in range(len(values)) if values[i:i+3]==['final',spec['local'],'='])
            end=values.index(';',start)
            expected=[['widget','.',spec['getter']],['_deps','.',spec['getter'],'(',')']]
            if values[start:end] not in expected:errors.append('Catalog assigned host callback wrapped or changed: '+str(spec))
        except (KeyError,StopIteration,ValueError):errors.append('Missing catalog host assignment: '+str(spec))
    spec=config.get('catalog_rail_callback')
    if spec:
        try:
            values=tokens(node_for(spec['member']))
            start=next(i+3 for i in range(len(values)) if values[i:i+3]==['final',spec['local'],'='])
            expression=values[start:values.index(';',start)]
            target=node_for(spec['target'])
            prefix=['widget','.','onRecommendationTap','==','null','?','null',':']
            getter_prefix=['_deps','.','onRecommendationTap','(',')','==','null','?','null',':']
            actual=expression[len(prefix):] if expression[:len(prefix)]==prefix else expression[len(getter_prefix):] if expression[:len(getter_prefix)]==getter_prefix else []
            aliases=config.get('callback_receiver_aliases',{})
            instances=config.get('callback_instances',{})
            path=''.join(actual)
            if len(actual)==1:path=instances.get(node_for(spec['member'])['owner'],'$State')+'.'+path
            else:
                for alias in sorted(aliases,key=len,reverse=True):
                    if path.startswith(alias+'.'):path=aliases[alias]+path[len(alias):];break
            expected=instances.get(target['owner'],'$State')+'.'+target['name']
            if path!=expected:errors.append('Catalog recommendation mapping tear-off changed')
        except (KeyError,StopIteration,ValueError):errors.append('Missing catalog recommendation callback assignment')
    if 'catalog_original_top_level_comments' in config:
        from collections import Counter
        expected=Counter(config['catalog_original_top_level_comments'])
        actual=Counter(token['text'] for (file,owner,name),node in lookup.items()
                       if not owner and file!='<original>'
                       for token in node['tokens'] if token['comment'])
        if actual!=expected:errors.append('Catalog original top-level comment bytes/counts changed')
    for member,expected in config.get('catalog_original_comments',{}).items():
        try:
            actual=[token['text'] for token in node_for(member)['tokens'] if token['comment']]
            if actual!=expected:errors.append('Catalog original comment bytes changed: '+member)
        except (KeyError,StopIteration):errors.append('Missing catalog original comment owner: '+member)
    state='_CatalogItemDetailScreenState.'
    for member,call,count in [('didChangeDependencies','subscribe',2),('dispose','unsubscribe',1)]:
        try:
            values=tokens(node_for(state+member));sites=argument_ranges(values,call)
            if len(sites)!=1 or len(sites[0])!=count or values[slice(*sites[0][0])]!=['this']:
                errors.append('Catalog route subscriber must be the State: '+member)
        except (KeyError,StopIteration):errors.append('Missing catalog route declaration: '+member)
    return errors
