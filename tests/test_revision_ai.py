"""v0.11 plans and prompt transport; simulated provider, never a real model run."""
import json
import sys
import time
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'external'))
import bridge

class RevisionPlans(unittest.TestCase):
    def decision(self,steps):
        return json.dumps(dict(intent='command_plan',action='plan',dialogue='我会先尝试。',item=steps,quantity=None))

    def test_plan_schema(self):
        plans=[
            [dict(kind='tree',item='log',quantity=1)],
            [dict(kind='equip',item='axe',quantity=1)],
            [dict(kind='collect',item='rocks',quantity=3),dict(kind='collect',item='goldnugget',quantity=3),dict(kind='give',item='rocks',quantity=3),dict(kind='give',item='goldnugget',quantity=3)],
            [dict(kind='craft',item='cutstone',quantity=1,prepare=True,ensure=True),dict(kind='give',item='cutstone',quantity=1)]
        ]
        for plan in plans:self.assertEqual(bridge.parse_decision(self.decision(plan))[3],plan)
        for plan in ([],plans[0]*13,[dict(kind='tree',item='rocks',quantity=1)],
                     [dict(kind='equip',item='axe',quantity=2)],
                     [dict(kind='give',item='ybf_friendship_flower',quantity=1)],
                     [dict(kind='collect',item='gears',quantity=1)],
                     [dict(kind='craft',item='cutstone',quantity=1,prepare='yes')],
                     [dict(kind='give',item='rocks',quantity=True)]):
            with self.assertRaises(ValueError):bridge.parse_decision(self.decision(plan))

    def test_compound_result_transport(self):
        plan=[dict(kind='collect',item='rocks',quantity=3),dict(kind='collect',item='goldnugget',quantity=3),dict(kind='give',item='rocks',quantity=3),dict(kind='give',item='goldnugget',quantity=3)]
        targets=[dict(item='rocks',quantity=3),dict(item='goldnugget',quantity=3)]
        decision=json.dumps(dict(intent='command_goal',action='goal',dialogue='检查条件后准备',item=targets,quantity=None,deliver=True));payloads=[]
        class Reply:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def read(self,n):return json.dumps({'choices':[{'message':{'content':decision}}]}).encode()
        def provider(req,timeout):payloads.append(json.loads(req.data));return Reply()
        server=bridge.BridgeServer(('127.0.0.1',0));server.ai=True;server.api_key='test-only-placeholder'
        data=dict(protocol=bridge.PROTOCOL,request_id='compound',friend_id='2',friend_name='朋友',message='我想要一些石头和金子，找到后给我',conversation_id='w',game_state={})
        try:
            with patch.object(bridge,'urlopen',provider):
                server.submit(data)
                for _ in range(200):
                    if not server.running:break
                    time.sleep(.005)
            result=server.lookup('compound',server.instance_id)[1]
            self.assertEqual(result['item'],{'targets':targets,'deliver':True});self.assertEqual(result['action'],'goal')
            self.assertGreaterEqual(payloads[0]['max_tokens'],1024)
            prompt=payloads[0]['messages'][0]['content']
            for phrase in ('炖肉汤','bonestew','equipped=true','默认每种3个','砍一棵树','允许补齐工具材料','32'):
                self.assertIn(phrase,prompt)
        finally:server.server_close()
