package.path='my_best_friend/scripts/?.lua;'..package.path
function Class(base,ctor)
 if type(base)=='function' then ctor=base;base=nil end
 local cls={};cls.__index=cls
 setmetatable(cls,{__index=base,__call=function(c,...)local obj=setmetatable({},c);if ctor then ctor(obj,...)end;return obj end})
 return cls
end
package.loaded['ybf_alerts']={}
package.loaded['brains/ybf_friendbrain']={}
package.loaded['prefabs/player_common_extensions']={}
local Friend=require('components/ybf_friend')
local Follower=dofile('../reference/components/follower.lua')
local function entity()
 local e={components={},replica={follower={SetLeader=function()end}},listeners={},tasks={},asleep=false}
 function e:ListenForEvent(event,fn,source)self.listeners[event]=fn end
 function e:RemoveEventCallback(event,fn,source)if self.listeners[event]==fn then self.listeners[event]=nil end end
 function e:PushEvent(event)if self.listeners[event] then self.listeners[event](self)end end
 function e:DoTaskInTime(t,fn,arg)local task={cancelled=false,Cancel=function(c)c.cancelled=true end,run=function()fn(self,arg)end};self.tasks[#self.tasks+1]=task;return task end
 function e:IsAsleep()return self.asleep end
 function e:HasTag()return false end
 function e:IsValid()return true end
 e.Transform={GetWorldPosition=function()return 100,0,200 end}
 return e
end
TheWorld=entity();local inst=entity();local flower=entity();flower.components.inventoryitem={GetGrandOwner=function()return nil end}
inst.components.health={IsDead=function()return false end}
inst.components.locomotor={Stop=function()inst.stopped=true end}
local f=Friend(inst);inst.components.ybf_friend=f;f.active=true;f.flower=flower
local c=Follower(inst);inst.components.follower=c
f:ApplyMovementPolicy();assert(c.leader==flower and c._onleaderwake)
inst.asleep=true;inst:PushEvent('entitysleep');local old=c.porttask;assert(old)
assert(f:SetMode('wait'));assert(c.leader==nil and c.noleashing and old.cancelled and c.porttask==nil)
assert(f.wait_position.x==100 and f.wait_position.z==200)
-- Even a previously queued vanilla callback cannot port without leader.
old.run();assert(c.porttask==nil)
inst:PushEvent('entitysleep');assert(c.porttask==nil)
f:ApplyMovementPolicy();assert(c.leader==nil)
local data=f:OnSave();assert(data.mode=='wait' and data.wait_position.x==100)
assert(f:SetMode('follow'));assert(c.leader==flower and not c.noleashing and c._onleaderwake)
print('PASS vanilla follower queued port cancelled; wait sleep no re-leash; resume and saved mode')
