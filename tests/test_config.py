import importlib.util,json,threading,time,unittest,urllib.request,urllib.error,tempfile,io,logging
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('bridge',Path(__file__).parents[1]/'external/bridge.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
class ConfigTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.s=b.BridgeServer(('127.0.0.1',0));self.s.config_path=Path(self.tmp.name)/'api_key.txt';self.s.ai=True
  self.thread=threading.Thread(target=self.s.serve_forever,daemon=True);self.thread.start();self.url='http://127.0.0.1:%d'%self.s.server_address[1];self.op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 def tearDown(self):self.s.stopping.set();self.s.shutdown();self.s.server_close();self.thread.join(2);self.tmp.cleanup()
 def req(self,path,data=None,headers=None):
  r=urllib.request.Request(self.url+path,data=None if data is None else json.dumps(data).encode(),headers=headers or {})
  try:
   with self.op.open(r,timeout=2) as resp:return resp.status,json.load(resp)
  except urllib.error.HTTPError as e:return e.code,json.load(e)
 def test_save_status_and_local_guard(self):
  c,d=self.req('/config/status');self.assertEqual(c,200);self.assertFalse(d['configured'])
  key='sk-test-secret-only-local';token=d['token']
  self.assertEqual(self.req('/config/save',{'key':key})[0],403)
  self.assertEqual(self.req('/config/status',headers={'Origin':'https://example.com'})[0],403)
  self.assertEqual(self.req('/config/save',{'token':token,'key':key},headers={'Origin':'https://example.com'})[0],403)
  self.assertEqual(self.req('/config/save',{'token':token,'key':key})[0],200)
  self.assertEqual(self.s.config_path.read_text().strip(),key);self.assertEqual(self.s.api_key,key)
  self.assertTrue(self.req('/config/status')[1]['configured']);self.assertNotIn(key,json.dumps(self.req('/config/status')[1]))
  self.assertEqual(self.req('/config/save',{'token':token,'key':'bad\nvalue'})[0],400)
  self.assertEqual(self.s.api_key,key)
  self.assertEqual(self.req('/config/save',{'token':token,'key':'*'*32})[0],400)
  self.assertEqual(self.s.config_path.read_text().strip(),key)
 def test_save_failure_does_not_replace_key(self):
  self.s.api_key='previous';self.s.config_path=Path(self.tmp.name)/'missing'/'key.txt'
  self.assertEqual(self.s.save_key('sk-valid-format')[0],500);self.assertEqual(self.s.api_key,'previous')
 def test_async_success_usage_and_no_key_log(self):
  self.s.api_key='sk-private-test';records=io.StringIO();handler=logging.StreamHandler(records);logging.getLogger().addHandler(handler)
  def provider(req,timeout):
   self.assertEqual(timeout,20);self.assertEqual(json.loads(req.data)['max_tokens'],16);time.sleep(.05)
   return io.StringIO(json.dumps({'choices':[{'message':{'content':'你好'}}],'usage':{'prompt_tokens':8,'completion_tokens':2,'total_tokens':10}}))
  try:
   with patch.object(b,'urlopen',provider):
    start=time.monotonic();c,d=self.req('/config/test',{'token':self.s.config_token});self.assertEqual(c,200);self.assertLess(time.monotonic()-start,.05)
    self.assertEqual(self.req('/config/test',{'token':self.s.config_token})[0],409)
    time.sleep(.1);result=self.req('/config/test/'+d['test_id'])[1];self.assertEqual(result['state'],'done');self.assertEqual(result['total_tokens'],10);self.assertGreaterEqual(result['elapsed_ms'],50)
   self.assertNotIn(self.s.api_key,records.getvalue());self.assertNotIn(self.s.api_key,json.dumps(result))
  finally:logging.getLogger().removeHandler(handler)
 def test_invalid_key_error_and_retry(self):
  self.s.api_key='sk-test'
  with patch.object(b,'urlopen',side_effect=urllib.error.HTTPError('url',401,'private provider text',{},None)):
   c,d=self.req('/config/test',{'token':self.s.config_token});time.sleep(.03)
   self.assertEqual(self.req('/config/test/'+d['test_id'])[1]['error'],'invalid_key');self.assertFalse(self.s.config_busy)
 def test_missing_key_expiry_and_restart_token(self):
  self.assertEqual(self.req('/config/test',{'token':self.s.config_token})[0],400)
  self.s.config_tests['old']={'created':time.monotonic()-121,'state':'done'}
  self.assertEqual(self.req('/config/test/old')[0],404)
  old=self.s.config_token;self.s.config_token='new-instance'
  self.assertEqual(self.req('/config/save',{'token':old,'key':'sk-valid-value'})[0],403)
if __name__=='__main__':unittest.main()
