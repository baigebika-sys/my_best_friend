"""Strict intent decoding. Diagnostics contain structure, never raw model text."""
import json
import re

RESOURCES={'twigs','cutgrass','log','rocks','flint','goldnugget'}
RECIPES={'axe','pickaxe','cutstone','boards','rope','torch'}
ACTIONS={'command_wait':'wait','command_follow':'follow','command_pickup':'pickup','command_stop':'stop',
         'command_eat':'eat','command_collect':'collect','command_craft':'craft','command_give':'give',
         'command_plan':'plan','command_goal':'goal','command_resume':'resume','command_equip':'equip',
         'question':'none','chat':'none','unclear':'none'}
FIELDS={'intent','action','dialogue','item','quantity','deliver'}
STEP_FIELDS={'kind','item','quantity','prepare','ensure'}

class DecisionError(ValueError):
    def __init__(self,code,reason,path='$',category='decision_schema',structure=None):
        super().__init__(reason)
        self.code=code;self.reason=reason;self.path=path;self.category=category
        self.structure=structure or {}
    def diagnostic(self):
        return dict(category=self.category,code=self.code,path=self.path,reason=self.reason,structure=self.structure)

def shape(value):
    def typ(v):
        return 'null' if v is None else 'boolean' if isinstance(v,bool) else 'object' if isinstance(v,dict) else 'array' if isinstance(v,list) else 'string' if isinstance(v,str) else 'number' if isinstance(v,(int,float)) else 'other'
    result={'type':typ(value)}
    if isinstance(value,dict):
        keys=set(value);result['fields']={k:typ(value[k]) for k in sorted(keys & FIELDS)}
        result['unexpected_field_count']=len(keys-FIELDS)
        if isinstance(value.get('item'),list):
            result['entry_count']=len(value['item'])
            result['entries']=[{'type':typ(e),'fields':{k:typ(v) for k,v in e.items() if k in STEP_FIELDS},'unexpected_field_count':len(set(e)-STEP_FIELDS)} if isinstance(e,dict) else {'type':typ(e)} for e in value['item'][:3]]
    return result

def parse_decision(text):
    if not isinstance(text,str) or not text.strip():
        raise DecisionError('empty_content','模型没有返回非空文本',category='provider_envelope')
    try:d=json.loads(text)
    except json.JSONDecodeError as e:
        raise DecisionError('invalid_json','JSON语法错误：第%d行、第%d列'%(e.lineno,e.colno),category='decision_json',structure={'bytes':len(text.encode('utf-8')),'line':e.lineno,'column':e.colno}) from None
    structure=shape(d)
    def fail(code,reason,path='$'):raise DecisionError(code,reason,path,structure=structure)
    if not isinstance(d,dict):fail('object_required','顶层必须是JSON对象')
    intent=d.get('intent');action=d.get('action')
    if not isinstance(intent,str) or intent not in ACTIONS:fail('invalid_intent','intent必须是已定义的意图字符串','$.intent')
    if not isinstance(action,str) or action not in set(ACTIONS.values()):fail('invalid_action','action必须是已定义的动作字符串','$.action')
    expected={'intent','action','dialogue','item','quantity'}|({'deliver'} if intent=='command_goal' else set())
    # Non-action replies may carry a harmless unused goal flag. This is a
    # defined schema variant, not a second model request or action repair.
    if ACTIONS[intent]=='none' and 'deliver' in d:
        if d['deliver'] is not None and d['deliver'] is not False:fail('unexpected_deliver','闲聊或问题不能要求交付','$.deliver')
        expected.add('deliver')
    if set(d)!=expected:
        structure['missing_fields']=sorted(expected-set(d));structure['unexpected_field_count']=len(set(d)-expected)
        fail('invalid_fields','顶层字段缺失或多余；请按所选意图的规定字段返回')
    if not isinstance(d['dialogue'],str) or not d['dialogue'].strip():fail('invalid_dialogue','dialogue必须是非空字符串','$.dialogue')
    action=ACTIONS[intent]
    if action!='none' and d['action']!=action:fail('inconsistent_action','intent与action不匹配','$.action')
    def quantity(n,path,optional=False,limit=100):
        if optional and n is None:return
        if isinstance(n,bool) or not isinstance(n,int) or not 1<=n<=limit:fail('invalid_quantity','数量必须是1至%d的整数，不能是字符串、小数、布尔或null'%limit,path)
    def item(value,path):
        if not isinstance(value,str) or not re.fullmatch(r'[a-z0-9_]{1,80}',value):fail('invalid_item','物品必须是游戏prefab标识字符串',path)
        if value=='ybf_friendship_flower':fail('protected_item','不能交付或获取友谊小花',path)
    if action=='goal':
        if not isinstance(d['deliver'],bool):fail('invalid_deliver','deliver必须是布尔值','$.deliver')
        if isinstance(d['item'],list):
            if d['quantity'] is not None or not 1<=len(d['item'])<=3:fail('invalid_targets','多目标须为1至3个条目且顶层quantity为null','$.item')
            targets=d['item'];seen=set()
            for index,e in enumerate(targets):
                path='$.item[%d]'%index
                if not isinstance(e,dict) or set(e)!={'item','quantity'}:fail('invalid_target_fields','目标条目只能包含item与quantity',path)
                item(e['item'],path+'.item');quantity(e['quantity'],path+'.quantity')
                if e['item'] in seen:fail('duplicate_target','同一物品目标不能重复',path+'.item')
                seen.add(e['item'])
        else:
            item(d['item'],'$.item');quantity(d['quantity'],'$.quantity')
            targets=[{'item':d['item'],'quantity':d['quantity']}]
        # Internal normalized target data, not model-specified game action steps.
        return action,d['dialogue'],intent,{'targets':targets,'deliver':d['deliver']},None
    if action=='pickup':
        def pickup(value,n,path):
            if not isinstance(value,str) or value not in RESOURCES:fail('unsupported_resource','暂不支持此基础资源标识',path+'.item')
            quantity(n,path+'.quantity',optional=True)
        if isinstance(d['item'],list):
            if d['quantity'] is not None or not 1<=len(d['item'])<=3:fail('invalid_pickup_plan','拾取数组须有1至3项且顶层quantity为null','$.item')
            seen=set()
            for i,e in enumerate(d['item']):
                path='$.item[%d]'%i
                if not isinstance(e,dict) or set(e)!={'item','quantity'}:fail('invalid_pickup_entry','拾取条目字段应为item、quantity',path)
                pickup(e['item'],e['quantity'],path)
                if e['item'] in seen:fail('duplicate_target','拾取物品不能重复',path)
                seen.add(e['item'])
        else:pickup(d['item'],d['quantity'],'$')
    elif action=='plan':
        entries=d['item']
        if d['quantity'] is not None or not isinstance(entries,list) or not 1<=len(entries)<=12:fail('invalid_plan','旧计划须有1至12步，顶层quantity应为null','$.item')
        for i,e in enumerate(entries):
            path='$.item[%d]'%i
            if not isinstance(e,dict) or not {'kind','item','quantity'}<=set(e) or set(e)-STEP_FIELDS:fail('invalid_step_fields','步骤缺少必需字段或存在多余字段',path)
            kind=e['kind']
            if not isinstance(kind,str) or kind not in ('collect','craft','give','tree','equip'):fail('invalid_step_kind','步骤kind不支持',path+'.kind')
            item(e['item'],path+'.item');quantity(e['quantity'],path+'.quantity')
            if kind=='collect' and e['item'] not in RESOURCES:fail('unsupported_resource','采集资源不支持',path+'.item')
            if kind=='equip' and e['quantity']!=1:fail('invalid_equip_count','一次只能装备一个物品',path+'.quantity')
            if kind=='tree' and e['item']!='log':fail('invalid_tree_item','树目标标识必须为log',path+'.item')
            if kind=='craft' and e['item'] not in RECIPES:fail('unsupported_recipe','当前基础配方范围不支持此配方',path+'.item')
            if 'prepare' in e and not isinstance(e['prepare'],bool):fail('invalid_prepare','prepare必须是布尔值',path+'.prepare')
            if 'ensure' in e and (kind!='craft' or not isinstance(e['ensure'],bool)):fail('invalid_ensure','ensure只用于craft且必须是布尔值',path+'.ensure')
    elif action in ('collect','craft','give','equip'):
        item(d['item'],'$.item');quantity(d['quantity'],'$.quantity')
        if action=='collect' and d['item'] not in RESOURCES:fail('unsupported_resource','采集资源不支持','$.item')
        if action=='craft' and d['item'] not in RECIPES:fail('unsupported_recipe','当前基础配方范围不支持此配方','$.item')
        if action=='equip' and d['quantity']!=1:fail('invalid_equip_count','一次只能装备一个物品','$.quantity')
    elif action=='eat':
        item(d['item'],'$.item');quantity(d['quantity'],'$.quantity',limit=20)
    elif d['item'] is not None or d['quantity'] is not None:fail('unexpected_arguments','非工作意图的item与quantity必须为null')
    return action,d['dialogue'],intent,d['item'],d['quantity']
