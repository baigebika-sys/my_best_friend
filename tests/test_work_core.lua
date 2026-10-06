package.path='my_best_friend/scripts/?.lua;'..package.path
local Core=require('ybf_work_core')
local function fixture(goal)
 local f={now=0,items={},reports={},restores={},picks={},position={x=1,z=2}}
 f.o={now=function()return f.now end,timeout=60,position=function()return {x=f.position.x,z=f.position.z}end,
 capture=function()return 'wait',{x=0,z=0}end,enter=function()end,stop=function()end,busy=function()return false end,
 report=function(text)f.reports[#f.reports+1]=text end,restore=function(m,a)f.restores[#f.restores+1]={m,a}end,
 valid=function(t,c)return t.valid end,
 find=function(j)
  for _,t in ipairs(f.items)do if t.valid and (j.failed[t]or 0)<2 then
   if t.full then return nil,'背包满' end;return t
  end end
  return nil,'范围内没有更多可用目标'
 end,
 pickup=function(t,token,attempt,cb)f.picks[#f.picks+1]={t=t,token=token,cb=cb};end}
 f.core=Core.New(f.o);f.core:Start('twigs',goal,'树枝')
 function f:finish(n)local a=self.picks[#self.picks];self.core:Count(a.token,n);a.t.valid=false;a.cb(true)end
 return f
end
local f=fixture(10);f.items={{valid=true},{valid=true}};f.core:Tick();f:finish(6);f.position.x=999;assert(f.core.job.center.x==1);f.core:Tick();f:finish(4);f.core:Tick();assert(not f.core.job and f.restores[1][1]=='wait');assert(f.reports[1]:find('10'))
local g=fixture(10);g.items={{valid=true}};g.core:Tick();g:finish(6);g.core:Tick();assert(g.reports[1]:find('还差4个'))
local h=fixture(nil);h.items={{valid=true,full=true}};h.core:Tick();assert(not h.core.job and h.reports[1]:find('背包满'))
local i=fixture(10);i.items={{valid=true},{valid=true}};i.core:Tick();i.items[1].valid=false;i.core:Tick();assert(#i.picks==2);i:finish(10);i.core:Tick();assert(not i.core.job)
local j=fixture(10);j.items={{valid=true}};j.core:Tick();j.now=8;j.core:Tick();j.now=16;j.core:Tick();assert(not j.core.job and #j.picks==2)
local k=fixture(10);k.items={{valid=true}};k.core:Tick();local old=k.picks[1];k.core:End('取消',false);k.core:Start('twigs',2,'树枝');k.core:Count(old.token,99);old.cb(true);assert(k.core.job.count==0)
local l=fixture(nil);l.items={{valid=true}};l.core:Tick();l.now=60;l.core:Tick();assert(not l.core.job and l.reports[1]:find('时间上限'))
print('PASS fixed center, unit goal, shortfall, full, vanished target, bounded retries, cancelled late result, deadline')

local m=fixture(1);m.core.job.plan={{item='twigs',goal=1,label='树枝'},{item='cutgrass',goal=1,label='草'}}
m.items={{valid=true}};m.core:Tick();m:finish(1);m.now=59;m.core:Tick();assert(m.core.job.item=='cutgrass' and m.core.job.deadline==60 and #m.restores==0)
m.now=60;m.core:Tick();assert(not m.core.job and #m.restores==1 and m.reports[1]:find('时间上限'))
print('PASS mixed items share total deadline and restore previous waiting mode only once')
