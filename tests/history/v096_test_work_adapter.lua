package.path='my_best_friend/scripts/?.lua;'..package.path
function Class(ctor)local c={};c.__index=c;return setmetatable(c,{__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})end
TUNING={};GetTime=function()return 0 end;Vector3=function(x,y,z)return {x=x,y=y,z=z}end
local objects={};local notices={};local action
local inst={components={},Transform={GetWorldPosition=function()return 0,0,0 end},sg={HasStateTag=function()return false end}}
function inst:DoPeriodicTask(_,fn)return {Cancel=function()end}end
function inst:ClearBufferedAction()action=nil end
function inst:GetBufferedAction()return action end
function inst:GetDistanceSqToInst()return 1 end
function inst:YBFAnnounce(t)notices[#notices+1]=t end
local friend={active=true,mode='follow',name='朋友',ApplyMovementPolicy=function()end,SetMode=function(c,m)c.mode=m;return true end}
inst.components.ybf_friend=friend;inst.components.health={IsDead=function()return false end}
inst.components.locomotor={Stop=function()end,PushAction=function(_,a)action=a end,GoToPoint=function()end}
local units=40;local capacity=100
local old={prefab='twigs',components={stackable={StackSize=function()return units end}}}
inst.components.inventory={itemslots={old},CanAcceptCount=function()return capacity end,GetOverflowContainer=function()end}
ACTIONS={YBF_GROUND_PICKUP={},PICKUP={fn=function(a)units=units+a.target.n;a.target.valid=false;return true end}}
BufferedAction=function(doer,target,kind)return {doer=doer,target=target,action=kind,AddSuccessAction=function(c,f)c.success=f end,AddFailAction=function(c,f)c.fail=f end}end
TheSim={FindEntities=function()return objects end}
local function item(n)return {n=n,prefab='twigs',valid=true,components={inventoryitem={canbepickedup=true},stackable={StackSize=function()return n end}},Transform={GetWorldPosition=function()return 1,0,1 end},IsValid=function(c)return c.valid end,IsInLimbo=function()return false end}end
local Work=require('components/ybf_work');local w=Work(inst);inst.components.ybf_work=w
objects={item(6)};assert(w:Start('twigs',10));w:Tick();assert(action);assert(w:PerformPickup(action));action.success();action=nil;assert(w.core.job.count==6 and units==46);w:Tick();assert(not w.core.job and friend.mode=='follow' and notices[1]:find('还差4个'))
objects={item(6)};capacity=0;w:Start('twigs',10);w:Tick();assert(not w.core.job and not action and notices[2]:find('背包空间'))
objects={item(6),item(4)};capacity=100;w:Start('twigs',10);w:Tick();local lost=action.target;lost.valid=false;w:Tick();assert(action and action.target~=lost)
print('PASS actual work adapter excludes existing inventory, stack units, full capacity, vanished target reselection')

w:Cancel(false)
-- Exercise the real adapter boundary, rather than a radius constant in isolation.
local edge=item(1);edge.Transform.GetWorldPosition=function()return 12,0,0 end
local outside=item(1);outside.Transform.GetWorldPosition=function()return 12.01,0,0 end
objects={outside,edge};w:Start('twigs',1);w:Tick();assert(action.target==edge);w:Cancel(false)
objects={outside};w:Start('twigs',1);w:Tick();assert(not w.core.job and not action)
-- Actual grass prefab and mixed inventory accounting.
local grassunits=0
inst.components.inventory.itemslots[2]={prefab='cutgrass',components={stackable={StackSize=function()return grassunits end}}}
ACTIONS.PICKUP.fn=function(a)
 if a.target.prefab=='cutgrass' then grassunits=grassunits+a.target.n else units=units+a.target.n end
 a.target.valid=false;return true
end
local grass=item(1);grass.prefab='cutgrass';local twig=item(1)
objects={grass,twig};local startunits=units
assert(w:Start({{item='cutgrass',quantity=1},{item='twigs',quantity=1}}))
w:Tick();assert(action.target==grass);assert(w:PerformPickup(action));action.success();action=nil
local center=w.core.job.center;local deadline=w.core.job.deadline;local oldtoken=w.core.job.serial
w:Tick();assert(w.core.job.item=='twigs' and w.core.job.center==center and w.core.job.deadline==deadline)
w.core:Count(oldtoken,100);assert(w.core.job.count==0)
w:Tick();assert(action.target==twig);assert(w:PerformPickup(action));action.success();action=nil;w:Tick()
assert(not w.core.job and grassunits==1 and units==startunits+1 and friend.mode=='follow')
assert(notices[#notices]:find('1个草') and notices[#notices]:find('1个树枝'))
objects={};w:Start({{item='cutgrass',quantity=2},{item='twigs',quantity=1}});w:Tick();assert(w.core.job and w.core.job.item=='twigs');w:Tick();assert(not w.core.job and notices[#notices]:find('还差2个'))
objects={item(1)};capacity=0;w:Start({{item='twigs',quantity=1},{item='cutgrass',quantity=1}});w:Tick();assert(not w.core.job and notices[#notices]:find('未开始'))
capacity=100;objects={item(1)};w:Start({{item='twigs',quantity=1},{item='cutgrass',quantity=1}});w:Tick();local late=action
w:Cancel(true);assert(not w.core.job and friend.mode=='follow');late.success();assert(not w.core.job)
print('PASS radius 12 boundary, ground grass, mixed counts/fixed center/shared deadline, stale callbacks, shortfall, full abort, cancellation')
