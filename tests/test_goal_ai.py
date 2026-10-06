"""v0.12 parser + real local HTTP server, simulated provider (NOT model validation)."""
import json,logging,sys,time,threading,unittest,urllib.request
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'external'))
import bridge
from decision import DecisionError

def goal(**changes):
    d=dict(intent='command_goal',action='goal',dialogue='检查条件后准备',item='cutstone',quantity=1,deliver=True)
    d.update(changes);return json.dumps(d,ensure_ascii=False)

class Goals(unittest.TestCase):
    def test_target_only_normalization(self):
        result=bridge.parse_decision(goal())
        self.assertEqual(result[0],'goal');self.assertEqual(result[3],{'targets':[{'item':'cutstone','quantity':1}],'deliver':True})
        result=bridge.parse_decision(goal(item=[dict(item='rocks',quantity=3),dict(item='goldnugget',quantity=3)],quantity=None))
        self.assertEqual(len(result[3]['targets']),2)
    def test_precise_safe_diagnostics(self):
        cases=[(goal(quantity='1'),'invalid_quantity','$.quantity'),(goal(deliver='yes'),'invalid_deliver','$.deliver'),
               (goal(action='plan'),'inconsistent_action','$.action'),(goal(item='石砖'),'invalid_item','$.item'),
               (goal(item=[{'item':'rocks','quantity':2,'kind':'mine'}],quantity=None),'invalid_target_fields','$.item[0]'),
               (goal(item=[dict(item='rocks',quantity=1)]*2,quantity=None),'duplicate_target','$.item[1].item'),
               (goal(secret='KEY-MUST-NOT-LEAK'),'invalid_fields','$'),
               ('{"intent":"command_goal",','invalid_json','$')]
        for raw,code,path in cases:
            with self.assertRaises(DecisionError) as ctx:bridge.parse_decision(raw)
            self.assertEqual((ctx.exception.code,ctx.exception.path),(code,path))
            self.assertNotIn('KEY-MUST-NOT-LEAK',json.dumps(ctx.exception.diagnostic()))
    def test_http_invalid_never_dispatches_then_goal_idempotent(self):
        server=bridge.BridgeServer(('127.0.0.1',0));server.ai=True;server.api_key='PRIVATE-TEST-KEY-NEVER-LOG'
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        endpoint='http://127.0.0.1:%d'%server.server_address[1]
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}));calls=[];response=[goal(quantity='1')]
        class Reply:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def read(self,n):return json.dumps({'choices':[{'message':{'content':response[0]}}]}).encode()
        def provider(req,timeout):calls.append(json.loads(req.data));return Reply()
        def submit(key):
            data=dict(protocol=bridge.PROTOCOL,request_id=key,friend_id='2',friend_name='朋友',message='我想要一个石砖',conversation_id='world',game_state={'work':{'version':'0.12.0','radius':32},'inventory':{'items':[]}})
            with opener.open(urllib.request.Request(endpoint+'/tasks',data=json.dumps(data).encode()),timeout=2) as r:return json.load(r)
        def poll(key):
            for _ in range(100):
                with opener.open(endpoint+'/tasks/'+key+'?instance='+server.instance_id,timeout=2) as r:d=json.load(r)
                if d['state']!='pending':return d
                time.sleep(.005)
            self.fail('bounded polling exceeded')
        try:
            with patch.object(bridge,'urlopen',provider),self.assertLogs(level=logging.INFO) as logs:
                submit('invalid');bad=poll('invalid')
                self.assertEqual(bad['error'],'instruction_parse_failed');self.assertEqual(bad['diagnostic']['code'],'invalid_quantity')
                self.assertNotIn('action',bad);self.assertNotIn('item',bad)
                response[0]=goal();submit('valid');good=poll('valid')
                self.assertEqual(good['action'],'goal');self.assertEqual(good['item']['targets'][0]['item'],'cutstone')
                submit('valid');poll('valid');self.assertEqual(len(calls),2)
            self.assertNotIn(server.api_key,'\n'.join(logs.output))
            self.assertIn('category=decision_schema','\n'.join(logs.output));self.assertIn('path=$.quantity','\n'.join(logs.output))
            # Prompt assertion only checks responsibility contract, NOT natural-language interpretation.
            self.assertIn('不生成工具/采矿/科技/制作/交付步骤',calls[-1]['messages'][0]['content'])
        finally:server.shutdown();server.server_close();thread.join(2)
    def test_model_action_steps_rejected(self):
        s=bridge.BridgeServer(('127.0.0.1',0));s.ai=True;s.api_key='test-key'
        content=json.dumps(dict(intent='command_plan',action='plan',dialogue='先采矿',item=[dict(kind='craft',item='cutstone',quantity=1,prepare=True)],quantity=None))
        class Reply:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def read(self,n):return json.dumps({'choices':[{'message':{'content':content}}]}).encode()
        try:
            with patch.object(bridge,'urlopen',lambda *a,**kw:Reply()):
                s.submit(dict(protocol=bridge.PROTOCOL,request_id='steps',friend_id='2',friend_name='朋友',message='我想要一个石砖'))
                for _ in range(100):
                    if not s.running:break
                    time.sleep(.005)
            d=s.lookup('steps',s.instance_id)[1]
            self.assertEqual(d['diagnostic']['code'],'model_steps_forbidden');self.assertNotIn('action',d)
        finally:s.server_close()
    def test_provider_failures_are_separate(self):
        cases=[(b'not-json','provider_json','invalid_provider_json'),(b'{}','provider_envelope','missing_content'),
               (json.dumps({'choices':[{'message':{'content':''}}]}).encode(),'provider_envelope','empty_content')]
        for raw,category,code in cases:
            class Reply:
                def __enter__(self):return self
                def __exit__(self,*args):pass
                def read(self,n):return raw
            s=bridge.BridgeServer(('127.0.0.1',0));s.ai=True;s.api_key='test-key'
            try:
                with patch.object(bridge,'urlopen',lambda *a,**kw:Reply()):
                    s.submit(dict(protocol=bridge.PROTOCOL,request_id='provider',friend_id='2',friend_name='朋友',message='石砖'))
                    for _ in range(100):
                        if not s.running:break
                        time.sleep(.005)
                d=s.lookup('provider',s.instance_id)[1]
                self.assertEqual((d['diagnostic']['category'],d['diagnostic']['code']),(category,code));self.assertNotIn('action',d)
            finally:s.server_close()
