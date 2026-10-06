package.path='my_best_friend/scripts/?.lua;'..package.path
function Class(ctor)local c={};c.__index=c;return setmetatable(c,{__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})end
FOODTYPE={GENERIC='GENERIC',MEAT='MEAT'};FOODGROUP={OMNI={name='omni',types={'GENERIC','MEAT'}}}
TUNING={STALE_FOOD_HUNGER=.5,STALE_FOOD_HEALTH=.5,SPOILED_FOOD_HUNGER=.25,SPOILED_FOOD_HEALTH=0,SANITY_SMALL=10,SPICE_MULTIPLIERS={}}
local now=0;GetTime=function()return now end;Vector3=function(x,y,z)return {x=x,y=y,z=z}end
local Edible=dofile('tests/reference/edible.lua');local Eater=dofile('tests/reference/eater.lua')
local Info=require('ybf_supply_info');local Core=require('ybf_needs_core');local Needs=require('components/ybf_needs');local Work=require('components/ybf_work')
local inst,needs,action,notices,objects
local function stat(key)
 local c={current=100,currenthealth=key=='health' and 100 or nil,max=100,maxhealth=key=='health' and 100 or nil}
 function c:DoDelta(n)if key=='health' then self.currenthealth=math.max(0,math.min(100,self.currenthealth+n))else self.current=math.max(0,math.min(100,self.current+n))end end
 function c:IsDead()return self.currenthealth and self.currenthealth<=0 end
 function c:GetMaxWithPenalty()return 100 end
 return c
end
local function reset()
 now=0;action=nil;notices={};objects={}
 inst={components={},Transform={GetWorldPosition=function()return 0,0,0 end},sg={HasStateTag=function(_,tag)return false end}}
 function inst:HasTag()return false end
 function inst:PushEvent()end
 function inst:GetBufferedAction()return action end
 function inst:ClearBufferedAction()action=nil end
 function inst:PushBufferedAction(a)action=a end
 function inst:DoPeriodicTask()return {Cancel=function()end}end
 function inst:GetDistanceSqToInst()return 1 end
 function inst:YBFAnnounce(s)notices[#notices+1]=s end
 inst.components.health=stat('health');inst.components.hunger=stat('hunger');inst.components.sanity=stat('sanity')
 inst.components.inventory={itemslots={},GetOverflowContainer=function()end,CanAcceptCount=function()return 999 end}
 inst.components.ybf_friend={active=true,name='朋友',mode='wait',wait_position={x=0,y=0,z=0},ApplyMovementPolicy=function()end,SetMode=function(c,m)c.mode=m end}
 inst.components.locomotor={Stop=function()end,GoToPoint=function()end,PushAction=function(_,a)action=a end}
 inst.components.eater=Eater(inst)
 needs=Needs(inst);inst.components.ybf_needs=needs
end
local function food(prefab,hunger,health,sanity,n)
 local item={prefab=prefab,valid=true,units=n or 1,components={},tags={edible_GENERIC=true},Transform={GetWorldPosition=function()return 1,0,0 end}}
 function item:IsValid()return self.valid end
 function item:IsInLimbo()return false end
 function item:HasTag(t)return self.tags[t]==true end
 function item:GetDisplayName()return self.prefab end
 function item:Remove()self.valid=false;self.units=0 end
 function item:PushEvent()end
 item.components.inventoryitem={canbepickedup=true,owner=inst}
 item.components.stackable={StackSize=function()return item.units end,Get=function()item.units=item.units-1;if item.units==0 then item.valid=false end;return {Remove=function()end}end}
 item.components.edible=Edible(item);local e=item.components.edible;e.hungervalue=hunger;e.healthvalue=health;e.sanityvalue=sanity
 return item
end
local function put(item)local slots=inst.components.inventory.itemslots;slots[#slots+1]=item;return item end
BufferedAction=function(doer,target,kind,item)return {doer=doer,target=target,action=kind,invobject=item,AddSuccessAction=function(c,f)c.success=f end,AddFailAction=function(c,f)c.fail=f end}end
ACTIONS={EAT={fn=function(a)return a.doer.components.eater:Eat(a.invobject)end},HEAL={fn=function(a)return a.invobject.components.healer:Heal(a.doer)end},YBF_GROUND_PICKUP={}}
ACTIONS.PICKUP={fn=function(a)a.target.components.inventoryitem.owner=inst;put(a.target);return true end}
TheSim={FindEntities=function()return objects end}
local function finish()
 local a=assert(action);local ok=a.action==ACTIONS.YBF_GROUND_PICKUP and inst.components.ybf_work:PerformPickup(a) or a.action.fn and a.action.fn(a)
 action=nil;if ok then a.success()else a.fail()end
end
reset();local berries=put(food('berries',20,1,0,10));needs:Tick();assert(not action and berries.units==10)
local snapshot=needs:Snapshot();assert(snapshot.items[1].effects.hunger==20 and snapshot.items[1].count==10)
inst.components.hunger.current=30;needs:Tick();assert(action.invobject==berries);finish();assert(inst.components.hunger.current==50 and berries.units==9)
now=2;needs:Tick();finish();now=4;needs:Tick();finish();assert(inst.components.hunger.current==90 and berries.units==7);now=6;needs:Tick();assert(not action and not needs.flags.hunger)
print('PASS full status stores food; local hunger hysteresis consumes one unit at a time and stops')
reset();inst.components.health.currenthealth=40;local damage=put(food('monstermeat',20,-20,-15,4));local healerfood=put(food('pierogi',20,40,5,2));needs:Tick();assert(action.invobject==healerfood);finish();assert(inst.components.health.currenthealth==80);now=2;needs:Tick();finish();now=4;needs:Tick();assert(not action and damage.units==4)
reset();inst.components.sanity.current=20;local bad=put(food('red_cap',0,-20,0,2));local san=put(food('cooked_green_cap',0,-1,15,4));local good=put(food('taffy',0,0,30,4));needs:Tick();assert(action.invobject==good);finish();now=2;needs:Tick();finish();now=4;needs:Tick();assert(not action and inst.components.sanity.current==80 and san.units==4 and bad.units==2)
print('PASS injured and low sanity choose useful safe supply; harmful food never emergency-enabled')
reset();inst.components.health.currenthealth=40;local salve=food('healingsalve',0,0,0,3);salve.components.edible=nil
salve.components.healer={health=20,Heal=function(_,target)target.components.health:DoDelta(20);salve.components.stackable:Get():Remove();return true end};put(salve)
needs:Tick();assert(action.action==ACTIONS.HEAL);finish();assert(inst.components.health.currenthealth==60 and salve.units==2)
local unsupported=food('unknown_sanity_tool',0,0,0);unsupported.components.edible=nil;assert(not Info.Describe(inst,unsupported).supported)
print('PASS non-food medicine uses HEAL and consumes one; unsupported non-food rejected')
reset();local fresh=food('example',40,20,10);fresh.components.perishable={GetPercent=function()return .3 end,IsStale=function()return true end,IsSpoiled=function()return false end}
inst.components.eater:SetAbsorptionModifiers(.5,.75,2);inst.components.foodaffinity={GetAffinity=function()return 2 end,HasPrefabAffinity=function()return false end}
local d=Info.Describe(inst,fresh);assert(d.effects.hunger==30 and d.effects.health==5 and d.effects.sanity==0 and d.freshness==.3)
inst.components.hunger.current=0;inst.components.health.currenthealth=10;inst.components.sanity.current=10;put(fresh);assert(inst.components.eater:Eat(fresh));assert(inst.components.hunger.current==30 and inst.components.health.currenthealth==15 and inst.components.sanity.current==10)
reset();local monster=food('monstermeat',20,-20,-15);monster.tags.monstermeat=true;inst.components.eater.strongstomach=true;d=Info.Describe(inst,monster);assert(d.effects.health==0 and d.effects.sanity==0)
inst.components.eater.custom_stats_mod_fn=function()return 0,0,0 end;assert(not Info.Describe(inst,monster).known)
inst.components.eater.preferseating={};assert(not Info.Describe(inst,monster).can_eat)
print('PASS reference Edible/Eater freshness, absorption, affinity and damage immunity match real consumption; diet and unknown hooks guarded')
reset();inst.components.hunger.current=20;put(food('danger',20,-1,-1,20));needs:Tick();assert(not action and #notices==1)
for i=1,100 do now=now+1;needs:Tick() end;assert(#notices==1)
inst.components.hunger.current=90;needs:Tick();inst.components.hunger.current=20;needs:Tick();assert(#notices==2)
inst.components.hunger.current=90;needs:Tick();inst.components.hunger.current=20;needs:Tick();assert(#notices==2);now=now+60;needs:Tick();assert(#notices==3)
local saved=needs:SaveState();local reloaded=Needs(inst);reloaded:LoadState(saved);assert(reloaded.flags.hunger and reloaded.notified.hunger)
print('PASS no-supply help once per episode, cooldown, recovery rearming and saved policy state')
reset();local manual=put(food('berries',20,0,0,5));assert(needs:RequestEat('berries',2));needs:Tick();finish();now=2;needs:Tick();finish();assert(manual.units==3 and not needs.explicit and #notices==1);now=7;needs:Tick();assert(not action)
assert(not needs:RequestEat('missing',1));assert(not needs:RequestEat('berries',4))
assert(needs:RequestEat('berries',2));now=8;needs:Tick();local late=action;needs:CancelExplicit();finish();assert(not needs.explicit and #notices==1);now=10;needs:Tick();assert(not action)
print('PASS explicit eating bypasses thresholds but only specified units; missing food and stale request cannot continue')
reset();inst.components.hunger.current=30;local ration=put(food('berries',60,0,0,3))
local twig=food('twigs',0,0,0);twig.components.edible=nil;twig.components.inventoryitem.owner=nil;objects={twig}
local w=Work(inst);inst.components.ybf_work=w;assert(w:Start('twigs',1));w:Tick();assert(action.action==ACTIONS.EAT and w.core.job and not w.core.job.inflight)
finish();now=2;w:Tick();assert(action.action==ACTIONS.YBF_GROUND_PICKUP and w.core.job);finish();w:Tick();assert(not w.core.job);w:Tick();assert(not w.returning and inst.components.ybf_friend.mode=='wait' and ration.units==2)
print('PASS real work/needs adapters: eat between actions, continue pickup and restore original waiting mode')

reset();inst.components.hunger.current=20;local failing=put(food('refused',40,0,0,10));needs:Tick();local a=action;action=nil;a.fail();now=2;needs:Tick();assert(not action and #notices==1);now=10;needs:Tick();assert(action);a=action;action=nil;a.fail();now=100;needs:Tick();assert(not action and needs.failurecount[failing]==2)
reset();inst.components.hunger.current=20;put(food('waiting',40,0,0));needs:Tick();now=10;needs:Tick();assert(not action and not needs.pending)
print('PASS failed supply bounded to two attempts; stalled action times out')

reset();inst.components.hunger.current=30;put(food('berries',60,0,0,3));local w=Work(inst);inst.components.ybf_work=w;w:Start('twigs',1);put(food('twigs',0,0,0));w.core.job.count=1;needs:Tick();assert(not action);w:Tick();assert(not w.core.job);needs:Tick();assert(action and action.action==ACTIONS.EAT)
print('PASS finishing work cannot queue a supply action which task cleanup would cancel')
