"""v0.12.1 chat regression: simulated provider, not live AI verification."""
import json,sys,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'external'))
import bridge
from decision import DecisionError
from dialogue import public_dialogue,conversation_state
class Chat(unittest.TestCase):
    def test_none_with_unused_goal_flag(self):
        d=dict(intent='chat',action='none',dialogue='你好呀！',item=None,quantity=None)
        for flag in (False,None):self.assertEqual(bridge.parse_decision(json.dumps(dict(d,deliver=flag)))[0],'none')
        with self.assertRaises(DecisionError):bridge.parse_decision(json.dumps(dict(d,deliver=True)))
    def test_no_backend_notices_in_dialogue(self):
        self.assertEqual(public_dialogue('任务指令完成，用时100ms。你好呀！'),'你好呀！')
        self.assertEqual(public_dialogue('Task completed processing_ms=100\n你好。'),'你好。')
        self.assertEqual(public_dialogue('你好，用时100ms。'),'你好。')
        self.assertEqual(public_dialogue('100ms等于0.1秒。'),'100ms等于0.1秒。')
    def test_internal_runtime_fields_not_sent_to_model(self):
        state=dict(health={'current':90},time={'phase':'day','day':3},work={'radius':32,'last_summary':'给你了1个草。','last_result':{'task_id':1,'time':100,'audit':{'consumed':2},'count':1},'last_plan_result':{'steps':[]}})
        public=conversation_state(state)
        self.assertEqual(public['time']['day'],3);self.assertEqual(public['work']['last_result'],{'count':1})
        self.assertNotIn('last_plan_result',public['work']);self.assertIn('audit',state['work']['last_result'])
    def test_greeting_and_question_roundtrip(self):
        for intent,message,answer in [('chat','你好','你好呀！'),('question','你今天心情怎么样','和你待在一起很开心。')]:
            s=bridge.BridgeServer(('127.0.0.1',0));s.ai=True;s.api_key='test-key';payloads=[]
            decision=json.dumps(dict(intent=intent,action='none',dialogue=answer,item=None,quantity=None,deliver=False),ensure_ascii=False)
            class Reply:
                def __enter__(self):return self
                def __exit__(self,*args):pass
                def read(self,n):return json.dumps({'choices':[{'message':{'content':decision}}]}).encode()
            def provider(request,timeout):payloads.append(json.loads(request.data));return Reply()
            try:
                with patch.object(bridge,'urlopen',provider):
                    s.submit(dict(protocol=bridge.PROTOCOL,request_id='chat',friend_id='2',friend_name='朋友',message=message))
                    for _ in range(100):
                        if not s.running:break
                        time.sleep(.005)
                d=s.lookup('chat',s.instance_id)[1];self.assertEqual((d['action'],d['reply']),('none',answer))
                prompt=payloads[0]['messages'][0]['content'];self.assertIn('不要把所有话都当任务',prompt);self.assertIn('例如你好',prompt)
            finally:s.server_close()
