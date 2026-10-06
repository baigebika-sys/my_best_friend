-- Bounded dependency resolver. It produces one next action from actual world
-- state, never a fixed script for a particular finished product.
local Inventory=require('ybf_work_inventory')
local Resources=require('ybf_work_resources')
local Crafting=require('ybf_work_crafting')
local M={MAX_DEPTH=8,MAX_NODES=64,MAX_ACTIONS=240,MAX_RESUMES=3}
function M.New(inst,work)
 local self={}
 function self:Refresh(j)
  local total=0
  for _,target in ipairs(j.targets) do
   total=total+(j.deliver and (j.given[target.item] or 0) or math.min(target.quantity,Inventory.Count(inst,target.item,true)))
  end
  j.count=total
 end
 function self:Trace(j,item,required)
  local have=Inventory.Count(inst,item,true)
  local node={item=item,required=required,have=have,missing=math.max(0,required-have)}
  j.trace[#j.trace+1]=node
  return node
 end
 function self:Station(j,recipe)
  local builder=inst.components.builder
  j.phase='检查'..Inventory.Label(recipe.product)..'的解锁与科技条件'
  builder:EvaluateTechTrees()
  if builder:KnowsRecipe(recipe) or CanPrototypeRecipe(recipe.level,builder.accessible_tech_trees) then return true end
  if not builder:CanLearn(recipe.name) then return nil,'角色条件不允许解锁'..Inventory.Label(recipe.product),'recipe_condition' end
  local x,y,z=inst.Transform:GetWorldPosition()
  local found=TheSim:FindEntities(x,y,z,work.radius,nil,{'INLIMBO'})
  table.sort(found,function(a,b)return inst:GetDistanceSqToInst(a)<inst:GetDistanceSqToInst(b) end)
  for _,entity in ipairs(found) do
   local proto=entity.components.prototyper
   if proto and (not proto.restrictedtag or inst:HasTag(proto.restrictedtag))
    and Resources.InRange(inst,entity,j.center,work.radius)
    and CanPrototypeRecipe(recipe.level,proto.trees) and (j.failed[entity] or 0)<2 then
    j.step='tech';j.techrecipe=recipe.name;j.recipe=recipe.name;j.collectitem=nil;j.invobject=nil
    j.phase='靠近可解锁'..Inventory.Label(recipe.product)..'的科技站'
    return entity
   end
  end
  return nil,'尚未解锁'..Inventory.Label(recipe.product)..'；'..work.radius..'单位范围内没有满足实际配方科技要求的可达科技站','missing_technology'
 end
 local ensure
 ensure=function(j,item,required,path,depth)
  j.visits=j.visits+1
  if depth>M.MAX_DEPTH or j.visits>M.MAX_NODES then return nil,'依赖拆解超过深度或节点上限','dependency_limit' end
  if Inventory.Count(inst,item,true)>=required then return true end
  self:Trace(j,item,required)
  j.phase='补齐'..Inventory.Label(item)..'：缺'..math.max(0,required-Inventory.Count(inst,item,true))
  if Crafting.allowed[item] then
   local x,y,z=inst.Transform:GetWorldPosition()
   local loose=TheSim:FindEntities(x,y,z,work.radius,nil,{'INLIMBO'})
   table.sort(loose,function(a,b)return inst:GetDistanceSqToInst(a)<inst:GetDistanceSqToInst(b) end)
   for _,entity in ipairs(loose) do
    local invitem=entity.components.inventoryitem
    if entity.prefab==item and invitem and not invitem.owner and invitem.canbepickedup
      and Resources.InRange(inst,entity,j.center,work.radius) and (j.failed[entity] or 0)<2
      and inst.components.inventory:CanAcceptCount(entity)>=Inventory.Size(entity) then
     j.step='pickup';j.collectitem=item;j.invobject=nil;j.recipe=nil
     j.phase='优先拾取现成'..Inventory.Label(item)
     return entity
    end
   end
  end
  if path[item] then return nil,'检测到循环依赖：获取'..Inventory.Label(item)..'又需要其自身前置条件；需先有可拾取材料或可用工具','dependency_cycle' end
  local nextpath={};for key in pairs(path) do nextpath[key]=true end;nextpath[item]=true
  if Resources.labels[item] then
   local state=j.resource_states[item]
   if not state then state={kind='collect',item=item,label=Resources.labels[item],center=j.center,failed=j.failed};j.resource_states[item]=state end
   state.failed=j.failed;state.goal=required
   state.awaitloot_until=j.lootitem==item and j.awaitloot_until or nil
   local candidates=Resources.Scan(inst,j.center,work.radius,item,'collect')
   local first
   local waiting=state.awaitloot_until and GetTime()<state.awaitloot_until
   for _,candidate in ipairs(candidates) do
    if (j.failed[candidate.target] or 0)<2 and (not waiting or candidate.step=='pickup') then
     local room=candidate.step=='pickup' and inst.components.inventory:CanAcceptCount(candidate.target)>=Inventory.Size(candidate.target)
       or candidate.step~='pickup' and Inventory.Room(inst,item,candidate.step=='pick' and (candidate.target.components.pickable.numtoharvest or 1) or 1)
     if room then first=candidate;break end
    end
   end
   if first and (first.step=='mine' or first.step=='chop') then
    local action=first.step=='mine' and ACTIONS.MINE or ACTIONS.CHOP
    local tool,why=work:Tool(action)
    if why then return nil,why,'tool_condition' end
    if not tool then
     local name=first.step=='mine' and 'pickaxe' or 'axe'
     if (j.toolbuilds or 0)>=8 then return nil,'本任务工具更换次数达到上限','tool_limit' end
     j.phase='准备'..Inventory.Label(name)..'以获取'..Inventory.Label(item)
     -- Existing unusable tools must not satisfy the missing usable-tool goal.
     local result,reason,code=ensure(j,name,Inventory.Count(inst,name,true)+1,nextpath,depth+1)
     if result~=true then
      if j.step=='craft' and j.recipe==name then j.autotool=true end
      return result,reason,code
     end
     return nil,'工具准备后仍不可使用，停止重复制作','tool_condition'
    end
   end
   local entity,reason,code=work:FindStep(state)
   if not entity then return nil,reason,code end
   for _,key in ipairs({'step','invobject','recipe','preferred','autotool'}) do j[key]=state[key] end
   j.collectitem=item;j.giveitem=nil
   j.phase='获取'..Inventory.Label(item)..'：已有'..Inventory.Count(inst,item,true)..'，目标'..required
   return entity
  end
  local info,reason,code=Crafting.PlanRecipe(inst,item)
  if not info then return nil,reason,code end
  local batches=math.ceil((required-Inventory.Count(inst,item,true))/info.output)
  -- Re-read after every action. A sub-tool can consume a parent ingredient;
  -- restart this loop on the next tick and replenish the actual missing amount.
  for _,ingredient in ipairs(info.ingredients) do
   local needed=ingredient.amount*batches
   if Inventory.Count(inst,ingredient.item)<needed then
    j.phase='准备'..Inventory.Label(item)..'材料：'..Inventory.Label(ingredient.item)
    local result,why,blocked=ensure(j,ingredient.item,needed,nextpath,depth+1)
    if result~=true then return result,why,blocked end
   end
  end
  local station,why,blocked=self:Station(j,info.recipe)
  if station~=true then return station,why,blocked end
  local ready,failure=Crafting.Check(inst,item)
  if not ready then return nil,failure,'craft_condition' end
  j.step='craft';j.recipe=item;j.collectitem=nil;j.giveitem=nil;j.invobject=nil;j.autotool=false
  j.phase='按实际配方制作'..Inventory.Label(info.recipe.product)
  return inst
 end
 function self:Resolve(j)
  self:Refresh(j)
  j.trace={};j.visits=0;j.collectitem=nil;j.giveitem=nil;j.autotool=false
  if (j.actions or 0)>=M.MAX_ACTIONS then return nil,'本任务动作次数达到上限，已保留物资与进度','action_limit' end
  for _,target in ipairs(j.targets) do
   local required=target.quantity-(j.deliver and (j.given[target.item] or 0) or 0)
   local result,reason,code=ensure(j,target.item,required,{},1)
   if result~=true then return result,reason,code end
  end
  if j.deliver then
   for _,target in ipairs(j.targets) do
    local remain=target.quantity-(j.given[target.item] or 0)
    if remain>0 then
     if not work:OwnerValid(j.owner) then return nil,'玩家暂时无法接收，已有物品保留','recipient_unavailable' end
     local x,_,z=j.owner.Transform:GetWorldPosition()
     if (x-j.center.x)^2+(z-j.center.z)^2>work.radius^2 then return nil,'玩家已离开本任务起点允许范围，成品保留','recipient_out_of_range' end
     if (j.failed[j.owner] or 0)>=2 then return nil,'返回交付多次未成功或无法到达，成品保留','recipient_unreachable' end
     local entity=j.owner
     local gift=work:GiftItem(target.item)
     if not gift then return nil,'指定物品实际库存不足，重新检查前置条件','inventory_changed' end
     j.step='give';j.giveitem=target.item;j.givegoal=remain;j.collectitem=nil;j.invobject=gift
     j.phase='返回并交付'..Inventory.Label(target.item)..'×'..remain
     return entity
    end
   end
  end
  return nil,'目标已完成','complete'
 end
 function self:Gift(j,item,count)
  j.given[item]=(j.given[item] or 0)+count;self:Refresh(j)
 end
 function self:Feedback(j,reason)
  local delivered,held,missing={},{},{}
  for _,target in ipairs(j.targets) do
   local given=j.given[target.item] or 0
   local have=Inventory.Count(inst,target.item,true)
   if given>0 then delivered[#delivered+1]=given..'个'..Inventory.Label(target.item) end
   if have>0 then held[#held+1]=have..'个'..Inventory.Label(target.item) end
   local need=math.max(0,target.quantity-given-have)
   if need>0 then missing[#missing+1]=need..'个'..Inventory.Label(target.item) end
  end
  if reason=='目标已完成' or reason=='已达到目标数量' then
   return j.deliver and ('给你了'..table.concat(delivered,'和')..'。') or ('收集好了'..table.concat(held,'和')..'，我先保管着。')
  end
  local text=reason=='任务已停止' and '好，我停下了。' or tostring(reason)..'。'
  if #delivered>0 then text=text..'已给你'..table.concat(delivered,'和')..'。' end
  local stock={};local names={}
  for _,entity in ipairs(Inventory.Items(inst,true)) do stock[entity.prefab]=(stock[entity.prefab] or 0)+Inventory.Size(entity) end
  for name in pairs(stock) do names[#names+1]=name end;table.sort(names)
  local owned={};for index=1,math.min(8,#names) do local name=names[index];owned[#owned+1]=stock[name]..'个'..Inventory.Label(name) end
  if #owned>0 then text=text..'我还保留着'..table.concat(owned,'、')..'。' end
  if #missing>0 then text=text..'还没备齐'..table.concat(missing,'和')..'。' end
  -- The leaf shortage is useful to the player; internal graph/phase stays in Status.
  local leaf=j.trace and j.trace[#j.trace]
  if leaf and leaf.missing>0 and not (j.targets[1] and leaf.item==j.targets[1].item) then
   text=text..'现在还缺'..leaf.missing..'个'..Inventory.Label(leaf.item)..'。'
  end
  return text
 end
 function self:Summary(j,reason)
  local owned={};local names={}
  for _,entity in ipairs(Inventory.Items(inst,true)) do owned[entity.prefab]=(owned[entity.prefab] or 0)+Inventory.Size(entity) end
  for name in pairs(owned) do names[#names+1]=name end;table.sort(names)
  local held={};for i=1,math.min(16,#names) do held[#held+1]=Inventory.Label(names[i])..'×'..owned[names[i]] end
  local targets={};local missing={};local delivered={}
  for _,target in ipairs(j.targets) do
   local given=j.given[target.item] or 0
   targets[#targets+1]=Inventory.Label(target.item)..'×'..target.quantity
   local need=math.max(0,target.quantity-given-Inventory.Count(inst,target.item,true))
   if need>0 then missing[#missing+1]=Inventory.Label(target.item)..'×'..need end
   if given>0 then delivered[#delivered+1]=Inventory.Label(target.item)..'×'..given end
  end
  local trace={};for _,node in ipairs(j.trace or {}) do if node.missing>0 then trace[#trace+1]=Inventory.Label(node.item)..'×'..node.missing end end
  return '目标：'..table.concat(targets,'、')..'；当前持有：'..(#held>0 and table.concat(held,'、') or '无')
   ..'；已交付：'..(#delivered>0 and table.concat(delivered,'、') or '无')
   ..'；成品/目标缺口：'..(#missing>0 and table.concat(missing,'、') or '已备齐')
   ..'；当前阶段：'..tostring(j.phase or '检查库存')..'；当前前置缺口：'..(#trace>0 and table.concat(trace,'→') or '无')..'；'..tostring(reason)
 end
 return self
end
return M
