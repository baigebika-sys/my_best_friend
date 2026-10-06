package.path="my_best_friend/scripts/?.lua;"..package.path
local Core=require('ybf_comm_core');local cases=0
local function fixture()
 local f={now=0,notices={},logs={},requests={},cancels={},watched=0}
 local function query(kind,cb)f.requests[#f.requests+1]={kind=kind,cb=cb}end
 local o={session='world',timeout=45,http_timeout=8,poll_interval=2,now=function()return f.now end,
  valid=function(r)return r.friend.alive and r.player.alive end,
  encode=function(d)f.payload=d;return 'body'end,decode=function(s)if s=='bad'then error('bad')end return f.data end,
  query=function(_,cb)query('submit',cb)end,poll=function(_,_,cb)query('poll',cb)end,
  cancel=function(id,instance)f.cancels[#f.cancels+1]={id,instance}end,
  log=function(id,status)f.logs[#f.logs+1]=status end,
  notify=function(r,status,ms,detail,reply)f.notices[#f.notices+1]={id=r.id,status=status,ms=ms,reply=reply}end,
  watch=function(r,cb)r.cancel=cb;f.watched=f.watched+1 end,unwatch=function()f.watched=f.watched-1 end}
 f.o=o;f.core=Core.New(o);f.ctx={friend={GUID=1,alive=true},player={alive=true},playerkey='p',name='朋友'}
 function f:send()local ok,id=self.core:Send(self.ctx,'你好');assert(ok);return id end
 function f:respond(i,id,state,code,instance)
  self.data={protocol='ybf-task-v1',request_id=id,task_id=id,friend_id='1',instance_id=instance or string.rep('a',32),state=state,action=self.action or 'none',reply='我收到你的消息了'}
  self.requests[i].cb('response',true,code or 200)
 end
 function f:clean()assert(self.core.count==0 and self.watched==0)end
 return f
end
local function case(name,fn)fn();cases=cases+1;print('PASS '..name)end
case('normal completed and duplicate callback',function()
 local f=fixture();local id=f:send();f:respond(1,id,'pending',202);f.now=2;f.core:Tick();f:respond(2,id,'done');local n=#f.notices;f:respond(2,id,'done');assert(#f.notices==n);f:clean()
end)
case('30s task polls every 2 seconds without overlapping',function()
 local f=fixture();local id=f:send();f:respond(1,id,'pending',202)
 for t=2,30,2 do f.now=t-.1;f.core:Tick();assert(#f.requests==t/2);f.now=t;f.core:Tick();local i=#f.requests;f.now=t+.1;f.core:Tick();assert(#f.requests==i);f.now=t;f:respond(i,id,t==30 and 'done' or 'pending')end
 assert(f.notices[#f.notices].ms==30000);f:clean()
end)
case('game 45s timeout and late response ignored',function()
 local f=fixture();local id=f:send();f:respond(1,id,'pending',202);f.now=44;f.core:Tick();f.now=45;f.core:Tick();assert(f.notices[#f.notices].status=='timeout');local n=#f.notices;f.now=46;f:respond(2,id,'done');assert(#f.notices==n and #f.cancels==1);f:clean()
end)
case('external processing timeout',function()
 local f=fixture();local id=f:send();f:respond(1,id,'pending',202);f.now=2;f.core:Tick();f:respond(2,id,'timeout');assert(f.notices[#f.notices].status=='timeout');f:clean()
end)
case('restart invalidates old task and new request works',function()
 local f=fixture();local id=f:send();f:respond(1,id,'pending',202);f.now=2;f.core:Tick();f:respond(2,id,'pending',409,string.rep('b',32));assert(f.notices[#f.notices].status=='error');f.now=3;local new=f:send();f:respond(3,new,'done',202,string.rep('b',32));f:clean()
end)
case('removal migration or death cancels pending poll',function()
 local f=fixture();local id=f:send();f:respond(1,id,'pending',202);f.now=2;f.core:Tick();f.core.pending[id].cancel('migration');local n=#f.notices;f:respond(2,id,'done');assert(#f.notices==n and #f.cancels==1);f:clean()
end)
case('cancel while submission in flight cancels late accepted task',function()
 local f=fixture();local id=f:send();f.core:Cancel(id,'removed');assert(#f.cancels==0);local n=#f.notices;f:respond(1,id,'pending',202);assert(#f.cancels==1 and #f.notices==n);f:clean()
end)
case('8s connection timeout then late ack cancellation',function()
 local f=fixture();local id=f:send();f.now=8;f.core:Tick();assert(f.notices[#f.notices].status=='error');f:respond(1,id,'pending',202);assert(#f.cancels==1);f:clean()
end)
case('wrong task friend or instance cannot display',function()
 for _,kind in ipairs({'task','friend','instance'})do local f=fixture();local id=f:send();f:respond(1,id,'pending',202);f.now=2;f.core:Tick();f.data={protocol='ybf-task-v1',request_id=id,task_id=kind=='task'and'wrong'or id,friend_id=kind=='friend'and'2'or'1',instance_id=string.rep(kind=='instance'and'b'or'a',32),state='done',reply='bad'};f.requests[2].cb('body',true,200);assert(f.notices[#f.notices].status=='error');f:clean()end
end)
case('two out of order requests stay matched',function()
 local f=fixture();local a=f:send();f.now=1;local b=f:send();f:respond(2,b,'done',202);f:respond(1,a,'done',202);assert(f.notices[#f.notices].id==b);f:clean()
end)
case('connection failure missing task invalid json',function()
 for _,code in ipairs({0,404})do local f=fixture();local id=f:send();f:respond(1,id,'pending',202);f.now=2;f.core:Tick();f.requests[2].cb(nil,code~=0,code);assert(f.notices[#f.notices].status=='error');f:clean()end
 local f=fixture();f:send();f.requests[1].cb('bad',true,202);f:clean()
end)
case('shutdown suppresses late reply, invalid lifecycle tick',function()
 local f=fixture();local id=f:send();f.core:Close();local n=#f.notices;f:respond(1,id,'done',202);assert(#f.notices==n);f:clean()
 local g=fixture();g:send();g.ctx.friend.alive=false;g.core:Tick();assert(g.notices[#g.notices].status=='cancelled');g:clean()
end)
case('rate limit and bounded requests',function()
 local f=fixture();f:send();assert(not f.core:Send(f.ctx,'你好'));for i=2,8 do f.ctx.friend={GUID=1,alive=true};f.now=i;f:send()end;f.now=9;assert(not f.core:Send(f.ctx,'你好'));f.core:Close();f:clean()
end)
print(cases..' task core cases passed')

case('latest opposite action only applied once; unknown action refused',function()
 local f=fixture();local actions={}
 f.o.apply=function(r,a,reply) actions[#actions+1]=a;return 'confirmed '..a end
 local a=f:send();f.now=1;local b=f:send();f.action='follow';f:respond(2,b,'done');f.action='wait';f:respond(1,a,'done')
 assert(#actions==1 and actions[1]=='follow');f:clean()
 f.now=2;local c=f:send();f.action='attack';f:respond(3,c,'done');assert(#actions==1 and f.notices[#f.notices].status=='error');f:clean()
end)
case('execution failure cannot announce success',function()
 local f=fixture();f.o.apply=function()error('failed')end;local a=f:send();f.action='wait';f:respond(1,a,'done');assert(f.notices[#f.notices].status=='error');f:clean()
end)
