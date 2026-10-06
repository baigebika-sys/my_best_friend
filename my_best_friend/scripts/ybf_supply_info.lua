local M={}
local healing={healingsalve=true,bandage=true}
function M.Stats(inst)
 local out={}
 for _,key in ipairs({"hunger","health","sanity"}) do
  local c=inst.components[key]
  if c then
   local maximum=key=="health" and c.GetMaxWithPenalty and c:GetMaxWithPenalty() or c.maxhealth or c.max or c.maxsanity
   out[key]={current=c.currenthealth or c.current or c.currentsanity,maximum=maximum}
  end
 end
 return out
end
function M.Items(inst)
 local list={};local seen={};local inv=inst.components.inventory
 local function add(slots)
  for _,item in pairs(slots or {}) do
   if item and item:IsValid() and not seen[item] then seen[item]=true;list[#list+1]=item end
  end
 end
 if inv then add(inv.itemslots);add({inv.activeitem});local overflow=inv:GetOverflowContainer();if overflow then add(overflow.slots) end end
 return list
end
function M.Describe(inst,item)
 local c=item.components;local edible=c.edible;local eater=inst.components.eater
 local d={prefab=item.prefab,name=item:GetDisplayName(),count=c.stackable and c.stackable:StackSize() or 1,
  kind="unsupported",supported=false,known=false,effects={hunger=0,health=0,sanity=0}}
 if c.perishable then d.freshness=c.perishable:GetPercent() end
 if edible and eater then
  d.kind="eat";d.can_eat=eater:CanEat(item) and eater:PrefersToEat(item)
  d.supported=d.can_eat;d.known=eater.custom_stats_mod_fn==nil
  local mult=inst.components.foodmemory and inst.components.foodmemory:GetFoodMultiplier(item.prefab) or 1
  for _,key in ipairs({"hunger","health","sanity"}) do
   local method=key=="health" and "GetHealth" or key=="hunger" and "GetHunger" or "GetSanity"
   local value=edible[method](edible,inst)
   if key~="hunger" and (edible[key.."value"] or 0)<0 and not eater:DoFoodEffects(item) then value=0 end
   local absorption=eater[key.."absorption"]
   if type(absorption)~="number" then d.known=false;absorption=1 end
   d.effects[key]=value*mult*absorption
  end
  d.unsafe=item:HasTag("unsafefood") or item:HasTag("spoiled")
  d.note="每份当前角色的基础效果估算；原版附加回调、温度、增益等不在三项数值内，使用后核对真实状态"
  if not d.known then d.note="角色自定义吸收效果未支持预测，不自动使用" end
 elseif healing[item.prefab] and c.healer and type(c.healer.health)=="number" then
  d.kind="heal";d.supported=not inst:HasTag("cannotheal");d.known=true;d.effects.health=c.healer.health
  d.note="通过原版治疗动作使用，实际恢复量以使用后状态为准"
 else d.note="本版未支持自动使用此非食物物品" end
 return d
end
return M
