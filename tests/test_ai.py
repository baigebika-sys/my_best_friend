import sys,json,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'external'))
import bridge
class Response:
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def read(self,n):return json.dumps({'choices':[{'message':{'content':json.dumps({'intent':'chat','action':'none','dialogue':'你好小树','item':None,'quantity':None},ensure_ascii=False)}}],'usage':{'prompt_tokens':100,'completion_tokens':10}}).encode()
class AI(unittest.TestCase):
    def test_history_state_and_failure(self):
        s=bridge.BridgeServer(('127.0.0.1',0));s.ai=True;s.api_key='test-placeholder'
        data=dict(protocol=bridge.PROTOCOL,request_id='1',friend_id='2',friend_name='小白',message='你好',conversation_id='world',game_state={'health':80})
        payloads=[]
        def call(req,timeout):payloads.append(json.loads(req.data));return Response()
        try:
            with patch.object(bridge,'urlopen',call):
                s.submit(data)
                for _ in range(100):
                    if not s.running:break
                    time.sleep(.005)
                self.assertEqual(s.lookup('1',s.instance_id)[1]['reply'],'你好小树')
                s.submit(dict(data,request_id='2',message='我叫什么'))
                for _ in range(100):
                    if not s.running:break
                    time.sleep(.005)
                self.assertEqual(len(payloads[1]['messages']),3)
                self.assertIn('current_instruction',payloads[0]['messages'][-1]['content'])
                self.assertIn('conversation_history',payloads[1]['messages'][1]['content'])
                self.assertEqual(payloads[0]['thinking']['type'],'disabled')
                self.assertIn('80',payloads[0]['messages'][-1]['content'])
            with patch.object(bridge,'urlopen',side_effect=ValueError('bad')):
                s.submit(dict(data,request_id='3'))
                for _ in range(100):
                    if not s.running:break
                    time.sleep(.005)
                self.assertEqual(s.lookup('3',s.instance_id)[1]['state'],'error')
        finally:s.server_close()

class Decisions(unittest.TestCase):
    def test_question_chat_unclear_never_change_mode(self):
        for intent in ('question','chat','unclear'):
            for action in ('none','wait','follow'):
                self.assertEqual(bridge.parse_decision(json.dumps(dict(intent=intent,action=action,dialogue='回答',item=None,quantity=None)))[0],'none')
    def test_explicit_commands_and_invalid_schema(self):
        for intent,action in [('command_wait','wait'),('command_follow','follow')]:
            self.assertEqual(bridge.parse_decision(json.dumps(dict(intent=intent,action=action,dialogue='请求',item=None,quantity=None)))[0],action)
        for d in [dict(intent='command_wait',action='follow',dialogue='bad'),dict(action='wait',dialogue='bad'),dict(intent='chat',action='attack',dialogue='bad')]:
            with self.assertRaises(ValueError):bridge.parse_decision(json.dumps(d))

class PickupSchema(unittest.TestCase):
 def test_supported_and_invalid(self):
  for item in ('twigs','cutgrass','log','rocks','flint','goldnugget'):
   self.assertEqual(bridge.parse_decision(json.dumps(dict(intent='command_pickup',action='pickup',dialogue='开始',item=item,quantity=10)))[3:],(item,10))
  for item,n in [('gears',10),('twigs',0),('twigs',True),('twigs',101),('twigs',1.5)]:
   with self.assertRaises(ValueError):bridge.parse_decision(json.dumps(dict(intent='command_pickup',action='pickup',dialogue='开始',item=item,quantity=n)))

class MixedSchema(unittest.TestCase):
 def test_mixed_plan(self):
  plan=[dict(item='cutgrass',quantity=1),dict(item='twigs',quantity=1)]
  self.assertEqual(bridge.parse_decision(json.dumps(dict(intent='command_pickup',action='pickup',dialogue='请求',item=plan,quantity=None)))[3],plan)
  for bad in [[],plan+plan,[dict(item='cutgrass',quantity=0)],[dict(item='grass',quantity=1)],[dict(item='twigs',quantity=1),dict(item='twigs',quantity=2)]]:
   with self.assertRaises(ValueError): bridge.parse_decision(json.dumps(dict(intent='command_pickup',action='pickup',dialogue='请求',item=bad,quantity=None)))

class EatSchema(unittest.TestCase):
 def test_eat_schema(self):
  self.assertEqual(bridge.parse_decision(json.dumps(dict(intent='command_eat',action='eat',dialogue='请求',item='berries',quantity=2)))[3:],('berries',2))
  for n in (None,0,21,True,1.5):
   with self.assertRaises(ValueError):bridge.parse_decision(json.dumps(dict(intent='command_eat',action='eat',dialogue='请求',item='berries',quantity=n)))
 def test_supply_prompt_and_snapshot(self):
  server=bridge.BridgeServer(('127.0.0.1',0));server.ai=True;server.api_key='placeholder'
  captured=[]
  data=dict(protocol=bridge.PROTOCOL,request_id='supply',friend_id='2',friend_name='朋友',message='你有什么吃的',conversation_id='world',game_state={'supplies':{'items':[{'prefab':'berries','effects':{'hunger':12.5},'freshness':.8}]}})
  def call(req,timeout):captured.append(json.loads(req.data));return Response()
  try:
   with patch.object(bridge,'urlopen',call):
    server.submit(data)
    for _ in range(100):
     if not server.running:break
     time.sleep(.005)
   self.assertIn('supplies',captured[0]['messages'][-1]['content'])
   self.assertIn('12.5',captured[0]['messages'][-1]['content'])
   self.assertIn('command_eat',captured[0]['messages'][0]['content'])
   self.assertIn('普通给予仅保管',captured[0]['messages'][0]['content'])
  finally:server.server_close()

class SupplyPayloadLimit(unittest.TestCase):
 def test_larger_snapshot_is_bounded_and_accepted(self):
  import threading,urllib.request,urllib.error
  server=bridge.BridgeServer(('127.0.0.1',0));thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
  base='http://127.0.0.1:%d'%server.server_address[1]
  data=dict(protocol=bridge.PROTOCOL,request_id='large-supplies',friend_id='2',friend_name='朋友',message='你有什么吃的',game_state={'supplies':{'items':[{'prefab':'food'+str(i),'note':'补给效果'*40,'effects':{'health':1,'hunger':20,'sanity':0}} for i in range(30)]}})
  raw=json.dumps(data,ensure_ascii=False).encode();self.assertGreater(len(raw),8192);self.assertLess(len(raw),32768)
  opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
  try:
   with opener.open(urllib.request.Request(base+'/tasks',data=raw),timeout=2) as response:self.assertEqual(response.status,200)
   with self.assertRaises(urllib.error.HTTPError) as error:opener.open(urllib.request.Request(base+'/tasks',data=b'x'*32769),timeout=2)
   self.assertEqual(error.exception.code,413)
  finally:server.shutdown();server.server_close();thread.join(2)
