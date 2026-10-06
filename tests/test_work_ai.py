"""New work schemas and actual bridge request/result path; no external API/key."""
import json
import sys
import time
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'external'))
import bridge

class WorkDecisions(unittest.TestCase):
    def decision(self, action, item, count, intent=None):
        return json.dumps(dict(intent=intent or 'command_'+action, action=action,
                               dialogue='我先检查条件', item=item, quantity=count))

    def test_work_schemas(self):
        for action, item in [('collect','twigs'),('collect','cutgrass'),('collect','log'),
                             ('collect','rocks'),('collect','flint'),('collect','goldnugget'),
                             ('craft','pickaxe'),('craft','axe'),('craft','cutstone'),('give','rocks')]:
            self.assertEqual(bridge.parse_decision(self.decision(action,item,3))[0], action)
        for action in ('collect','craft','give'):
            for count in (None,0,101,True,1.2):
                with self.assertRaises(ValueError): bridge.parse_decision(self.decision(action,'rocks',count))
        for action,item in [('collect','gears'),('craft','science_machine'),('give','ybf_friendship_flower'),('give','../key')]:
            with self.assertRaises(ValueError): bridge.parse_decision(self.decision(action,item,1))
        self.assertEqual(bridge.parse_decision(self.decision('pickup','rocks',3))[0], 'pickup')
        for intent in ('chat','question','unclear'):
            for action in ('collect','craft','give'):
                self.assertEqual(bridge.parse_decision(self.decision(action,None,None,intent))[0],'none')

    def test_bridge_roundtrip_and_prompt(self):
        for action,item,text in [('collect','goldnugget','开采并收集3个金块'),
                                 ('craft','pickaxe','用现有材料做一把鹤嘴锄'),
                                 ('give','rocks','给我3块石头')]:
            payloads=[]
            decision=self.decision(action,item,3)
            class Reply:
                def __enter__(self): return self
                def __exit__(self,*args): pass
                def read(self,n): return json.dumps({'choices':[{'message':{'content':decision}}]}).encode()
            def call(req,timeout):payloads.append(json.loads(req.data));return Reply()
            s=bridge.BridgeServer(('127.0.0.1',0));s.ai=True;s.api_key='fake-provider-no-real-key'
            data=dict(protocol=bridge.PROTOCOL,request_id=action,friend_id='2',friend_name='朋友',
                      message=text,conversation_id='w',game_state={'work':{'radius':12,'nearby':[]}})
            try:
                with patch.object(bridge,'urlopen',call):
                    s.submit(data)
                    for _ in range(200):
                        if not s.running:break
                        time.sleep(.005)
                result=s.lookup(action,s.instance_id)[1]
                self.assertEqual((result['action'],result['item'],result['quantity']),(action,item,3))
                prompt=payloads[0]['messages'][0]['content']
                for phrase in ('command_goal','command_craft','deliver','允许补齐工具材料','普通给予仅保管'):
                    self.assertIn(phrase,prompt)
                self.assertNotIn('不会采植物',prompt)
                self.assertIn('radius',payloads[0]['messages'][-1]['content'])
            finally:s.server_close()

if __name__=='__main__':unittest.main()
