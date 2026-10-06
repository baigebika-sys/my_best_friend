import importlib.util,json,threading,time,unittest,urllib.request,urllib.error
from pathlib import Path
from unittest.mock import Mock
spec=importlib.util.spec_from_file_location('bridge',Path(__file__).parents[1]/'external/bridge.py');bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
class Tests(unittest.TestCase):
 def setUp(self):
  self.s=bridge.BridgeServer(('127.0.0.1',0));self.th=threading.Thread(target=self.s.serve_forever,daemon=True);self.th.start()
  self.url='http://127.0.0.1:%d'%self.s.server_address[1];self.op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 def tearDown(self):self.s.shutdown();self.s.server_close();self.th.join(2)
 def request(self,path,data=None):
  req=urllib.request.Request(self.url+path,data=None if data is None else json.dumps(data,ensure_ascii=False).encode())
  try:
   with self.op.open(req,timeout=2) as r:return r.status,json.load(r)
  except urllib.error.HTTPError as e:return e.code,json.load(e)
 def payload(self,key='session-1'):return dict(protocol=bridge.PROTOCOL,request_id=key,friend_id='123',friend_name='朋友',message='你好')
 def poll(self,d,cancel=False):return self.request('/tasks/'+d['task_id']+('/cancel' if cancel else '')+'?instance='+d['instance_id'],{} if cancel else None)
 def test_normal_and_idempotency(self):
  c,d=self.request('/tasks',self.payload());self.assertEqual(c,200)
  time.sleep(.03);self.assertEqual(self.poll(d)[1]['reply'],bridge.REPLY)
  self.assertEqual(self.request('/tasks',self.payload())[1]['task_id'],d['task_id'])
  self.assertEqual(self.request('/tasks',self.payload()|{'message':'changed'})[0],409)
 def test_long_processing_short_submit_health_and_poll(self):
  self.s.delay=.25;t=time.monotonic();_,d=self.request('/tasks',self.payload());self.assertLess(time.monotonic()-t,.2)
  self.assertEqual(self.poll(d)[1]['state'],'pending');self.assertTrue(self.request('/health')[1]['ok'])
  time.sleep(.3);self.assertEqual(self.poll(d)[1]['state'],'done')
 def test_external_timeout(self):
  self.s.delay=.3;self.s.task_timeout=.08;_,d=self.request('/tasks',self.payload());time.sleep(.12)
  self.assertEqual(self.poll(d)[1]['state'],'timeout')
 def test_cancel_stops_simulation_and_new_task_works(self):
  self.s.delay=.5;_,d=self.request('/tasks',self.payload());self.assertEqual(self.poll(d,True)[1]['state'],'cancelled')
  time.sleep(.03);self.assertEqual(self.s.running,0)
  self.s.delay=0;_,new=self.request('/tasks',self.payload('new'));time.sleep(.03);self.assertEqual(self.poll(new)[1]['state'],'done')
 def test_restart_identity_and_missing(self):
  _,d=self.request('/tasks',self.payload());old=self.s.instance_id;self.s.instance_id='f'*32
  self.assertEqual(self.poll(d)[0],409)
  self.assertEqual(self.request('/tasks/missing?instance='+self.s.instance_id)[0],404)
 def test_actual_new_server_rejects_old_instance_and_accepts_new(self):
  self.s.delay=1;_,old=self.request('/tasks',self.payload())
  second=bridge.BridgeServer(('127.0.0.1',0));th=threading.Thread(target=second.serve_forever,daemon=True);th.start()
  original=self.url;self.url='http://127.0.0.1:%d'%second.server_address[1]
  try:
   self.assertEqual(self.poll(old)[0],409)
   _,new=self.request('/tasks',self.payload('new-session'));time.sleep(.03)
   self.assertEqual(self.poll(new)[1]['state'],'done')
  finally:
   self.url=original;second.shutdown();second.server_close();th.join(2)
 def test_expiry_and_capacity(self):
  self.s.retention=.05;_,d=self.request('/tasks',self.payload());time.sleep(.09);self.assertEqual(self.poll(d)[0],404)
  self.s.delay=1
  for i in range(8):self.assertEqual(self.request('/tasks',self.payload('busy-'+str(i)))[0],200)
  self.assertEqual(self.request('/tasks',self.payload('overflow'))[0],503)
 def test_invalid_and_socket_errors(self):
  self.assertEqual(self.request('/tasks',{})[0],400)
  for error in (ConnectionAbortedError(10053,'abort'),ConnectionResetError(),BrokenPipeError(),TimeoutError()):
   h=object.__new__(bridge.Handler);h.send_response=Mock();h.send_header=Mock();h.end_headers=Mock();h.wfile=Mock();h.wfile.write.side_effect=error
   with self.assertLogs(level='INFO'):self.assertFalse(h.respond(200,{'request_id':'x'}))
if __name__=='__main__':unittest.main()
