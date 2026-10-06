local Core=require("ybf_needs_core")
local Info=require("ybf_supply_info")
local help={hunger="我饿了，背包里没有合适的食物，可以给我些吃的吗？",health="我受伤了，没有合适的补给，可以给我治疗药膏或回血食物吗？",sanity="我精神不太好了，有恢复精神的食物吗？"}
local Needs=Class(function(self,inst)
 self.inst=inst;self.flags={};self.notified={};self.lasthelp={};self.failed=setmetatable({},{__mode="k"});self.failurecount=setmetatable({},{__mode="k"})
 self.rules={};self.serial=0;self.nextuse=0;self.pending=nil;self.explicit=nil
 for key,r in pairs(Core.defaults) do
  local cfg=TUNING.YBF_NEEDS or {};self.rules[key]={trigger=cfg[key.."_trigger"] or r.trigger,target=cfg[key.."_target"] or r.target,weight=r.weight}
 end
 for key,r in pairs(self.rules) do
  if r.trigger>=r.target then
   r.trigger=Core.defaults[key].trigger;r.target=Core.defaults[key].target
   print("[YBF NEEDS] invalid thresholds for "..key..", using defaults")
  end
 end
 self.cooldown=(TUNING.YBF_NEEDS or {}).help_cooldown or 60
end)
function Needs:Announce(text)self.inst:YBFAnnounce("["..self.inst.components.ybf_friend.name.."] "..text)end
function Needs:Snapshot()
 local list={};for _,item in ipairs(Info.Items(self.inst)) do if #list<30 then list[#list+1]=Info.Describe(self.inst,item) end end
 return {items=list,needs=self.flags,rules=self.rules,last_use=self.last_use}
end
function Needs:CancelExplicit()
 self.serial=self.serial+1;self.explicit=nil -- Already consumed units are not undone.
end
function Needs:RequestEat(prefab,n)
 if type(prefab)~="string" or type(n)~="number" or n%1~=0 or n<1 or n>20 then return false,"进食参数无效" end
 local available=0
 for _,item in ipairs(Info.Items(self.inst)) do
  if item.prefab==prefab then local d=Info.Describe(self.inst,item);if d.kind=="eat" and d.can_eat then available=available+d.count end end
 end
 if available<n then return false,"背包中没有足够数量、且当前角色能食用的指定食物" end
 self:CancelExplicit();self.explicit={prefab=prefab,remaining=n,used=0,serial=self.serial,deadline=GetTime()+60}
 return true
end
function Needs:CanAct()
 local i=self.inst;local f=i.components.ybf_friend;local w=i.components.ybf_work
 local j=w and w.core.job
 return f and f.active and not f.dead and not f.finished and not i.components.health:IsDead()
  and i.sg and not i.sg:HasStateTag("busy") and not i.sg:HasStateTag("dead") and not i.sg:HasStateTag("working")
  and not i.sg:HasStateTag("prechop") and not i.sg:HasStateTag("premine")
  and i:GetBufferedAction()==nil and not self.pending
  and not (w and (w.returning or j and not j.blocked and (j.inflight or j.goal and j.count>=j.goal or GetTime()>=j.deadline)))
end
function Needs:Use(item,d,request)
 local inst=self.inst;local before=Info.Stats(inst)
 local act=BufferedAction(inst,nil,d.kind=="eat" and ACTIONS.EAT or ACTIONS.HEAL,item)
 local marker={};self.pending=marker
 local oldcount=0;for _,v in ipairs(Info.Items(inst)) do if v.prefab==item.prefab then oldcount=oldcount+(v.components.stackable and v.components.stackable:StackSize() or 1)end end
 local function finish(ok,timedout)
  if self.pending~=marker then return end
  self.pending=nil;self.nextuse=GetTime()+2
  local aftercount=0;for _,v in ipairs(Info.Items(inst)) do if v.prefab==item.prefab then aftercount=aftercount+(v.components.stackable and v.components.stackable:StackSize() or 1)end end
  local consumed=oldcount-aftercount
  if not ok or consumed~=1 then
   self.failurecount[item]=(self.failurecount[item] or 0)+1
   self.failed[item]=self.failurecount[item]>=2 and math.huge or GetTime()+10
  else self.failurecount[item]=nil;self.failed[item]=nil end
  local after=Info.Stats(inst)
  self.last_use={prefab=d.prefab,name=d.name,kind=d.kind,consumed=consumed,success=ok and consumed==1,before=before,after=after,time=GetTime()}
  print("[YBF SUPPLY] action="..d.kind.." item="..d.prefab.." consumed="..consumed.." health="..before.health.current.."->"..after.health.current.." hunger="..before.hunger.current.."->"..after.hunger.current.." sanity="..before.sanity.current.."->"..after.sanity.current)
  if request and self.explicit==request and request.serial==self.serial then
   if ok and consumed==1 then
    request.used=request.used+1;request.remaining=request.remaining-1
    if request.remaining<=0 then self.explicit=nil;self.nextuse=GetTime()+5;self:Announce("已吃了"..request.used.."份"..d.name.."。") end
   else self.explicit=nil;self:Announce((timedout and "进食等待超时" or "进食未成功").."；本次实际吃了"..request.used.."份，已停止。") end
  end
 end
 act:AddSuccessAction(function()finish(true)end);act:AddFailAction(function()finish(false)end)
 marker.finish=finish;marker.deadline=GetTime()+10
 inst:PushBufferedAction(act)
end
function Needs:Tick()
 local inst=self.inst;local f=inst.components.ybf_friend
 if not f or not f.active or f.dead or inst.components.health:IsDead() then return end
 local stats=Info.Stats(inst);Core.Update(self.flags,stats,self.rules)
 for _,key in ipairs(Core.keys) do if not self.flags[key] then self.notified[key]=nil end end
 if self.pending then
  if GetTime()>=self.pending.deadline then
   local marker=self.pending
   inst:ClearBufferedAction();marker.finish(false,true)
  end
  return
 end
 local request=self.explicit
 if request and GetTime()>=request.deadline then self.explicit=nil;self:Announce("进食任务达到时间上限；实际吃了"..request.used.."份。");request=nil end
 local selected,description;local best=-math.huge;local suitable={}
 for _,item in ipairs(Info.Items(inst)) do
  local d=Info.Describe(inst,item)
  local score=Core.Score(d,stats,self.flags,self.rules)
  if score and (self.failed[item] or 0)<=GetTime() then
   for _,key in ipairs(Core.keys) do if d.effects[key]>0 then suitable[key]=true end end
   if (self.failed[item] or 0)<=GetTime() and score>best then selected=item;description=d;best=score end
  end
  if request and d.prefab==request.prefab and d.kind=="eat" and d.can_eat and (self.failed[item] or 0)<=GetTime() then
   selected=item;description=d;break
  end
 end
 if request and (not selected or description.prefab~=request.prefab) then
  self.explicit=nil;self:Announce("指定食物已不足或不能食用；本次实际吃了"..request.used.."份。");return
 end
 if not request then
  for _,key in ipairs(Core.keys) do
   if self.flags[key] and not suitable[key] and not self.notified[key] and GetTime()-(self.lasthelp[key] or -math.huge)>=self.cooldown then
    self:Announce(help[key]);self.notified[key]=true;self.lasthelp[key]=GetTime();break
   end
  end
 end
 self.pause_requested=selected~=nil and GetTime()>=self.nextuse
 if selected and GetTime()>=self.nextuse and self:CanAct() then self:Use(selected,description,request) end
end
function Needs:SaveState()
 local out={flags={},notified={},cooldown={}}
 for _,key in ipairs(Core.keys) do
  out.flags[key]=self.flags[key]==true;out.notified[key]=self.notified[key]==true
  out.cooldown[key]=math.max(0,self.cooldown-(GetTime()-(self.lasthelp[key] or -math.huge)))
 end
 return out
end
function Needs:LoadState(data)
 if type(data)~="table" then return end
 for _,key in ipairs(Core.keys) do
  self.flags[key]=data.flags and data.flags[key]==true
  self.notified[key]=data.notified and data.notified[key]==true
  local remaining=math.min(self.cooldown,math.max(0,tonumber(data.cooldown and data.cooldown[key]) or 0))
  self.lasthelp[key]=GetTime()-(self.cooldown-remaining)
 end
end
function Needs:Stop()self:CancelExplicit();self.pending=nil end
function Needs:OnRemoveFromEntity()self:Stop() end
return Needs
