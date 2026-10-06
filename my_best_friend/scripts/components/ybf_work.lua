local Core = require('ybf_work_core')
local Safety = require('ybf_work_safety')
local GoalPlanner = require('ybf_goal_planner')
local Inventory = require('ybf_work_inventory')
local Resources = require('ybf_work_resources')
local Crafting = require('ybf_work_crafting')
local labels = Resources.labels
local Work = Class(function(self, inst)
    self.inst = inst
    self.radius = math.max(32,TUNING.YBF_PICKUP_RADIUS or 32)
    self.timeout = TUNING.YBF_PICKUP_TIMEOUT or 60
    self.planner=GoalPlanner.New(inst,self)
    self.core = Core.New({
        now=GetTime, timeout=self.timeout, settle=.25,
        position=function() return self:Position() end,
        valid=function(target, center, job) return self:ValidTarget(target, job) end,
        capture=function()
            if self.returning then return 'wait', self.returning.anchor end
            local c = inst.components.ybf_friend
            return c.mode, c.wait_position
        end,
        enter=function()
            self.returning = nil
            local c = inst.components.ybf_friend
            c.mode = 'work'
            c:ApplyMovementPolicy()
        end,
        stop=function() self:StopAction() end,
        report=function(text,job)
            self.last_report=text
            local complete=true
            for _,entry in ipairs(job.records) do if not entry.reached_goal then complete=false end end
            self.last_plan_result={task_id=job.id,reached_goal=complete,steps=job.records,summary=text}
            self:Announce(text)
        end,
        restore=function(mode, anchor) self:Restore(mode, anchor) end,
        describe=function(job, reason)
            if job.kind=='goal' then
                self.planner:Refresh(job)
                self.last_result={task_id=job.id,kind='goal',count=job.count,goal=job.goal,reason=reason,time=GetTime(),reached_goal=job.count>=job.goal and not job.fatal}
                return self.planner:Feedback(job,reason)
            end
            local prefix = job.kind=='tree' and '实际砍倒' or job.kind=='equip' and '已装备' or job.kind == 'give' and '实际交付' or job.kind == 'craft' and not job.ensure and '本次实际制作' or '当前持有'
            local unit=job.kind=='tree' and '棵' or '个'
            local text = prefix..job.count..unit..job.label
            if job.goal and job.count < job.goal then text = text..'，还差'..(job.goal-job.count)..unit end
            if job.id then
                self.last_result = {task_id=job.id,kind=job.kind,item=job.item,goal=job.goal,count=job.count,
                    reason=reason,time=GetTime(),audit=job.audit,
                    reached_goal=job.goal ~= nil and job.count >= job.goal and not job.fatal and (job.kind~='tree' or job.treeclean)}
            end
            return text..'；'..reason
        end,
        refresh=function(job)
            if job.kind=='goal' then self.planner:Refresh(job)
            elseif job.kind == 'tree' then job.count=job.workdone or 0
            elseif job.kind == 'equip' then
            elseif job.kind=='craft' and job.ensure then job.count=Inventory.Count(inst,job.item,true)
            elseif job.kind ~= 'craft' and job.kind ~= 'give' then
                job.count = Inventory.Count(inst, job.item)
            end
        end,
        complete=function(job) return job.kind~='tree' or job.treeclean end,
        block=function(job,reason,code) self:BlockGoal(job,reason,code) end,
        actiontime=function(target,job)
            return job.kind=='goal' and math.max(8,math.min(20,4+math.sqrt(inst:GetDistanceSqToInst(target))/6)) or 8
        end,
        busy=function() return self:ActionBusy() end,
        find=function(job) return self:FindStep(job) end,
        pickup=function(target, token, attempt, done) self:PushStep(target, token, attempt, done) end,
    })
    self.tick = inst:DoPeriodicTask(.25, function() self:Tick() end)
end)
function Work:Position()
    local x,y,z = self.inst.Transform:GetWorldPosition()
    return {x=x,y=y,z=z}
end
function Work:Announce(text)
    if self.inst.components.talker then self.inst.components.talker:Say(text) end
    self.inst:YBFAnnounce('['..self.inst.components.ybf_friend.name..'] '..text)
end
function Work:ActionBusy()
    local sg = self.inst.sg
    local needs = self.inst.components.ybf_needs
    return self.inst:GetBufferedAction() ~= nil or needs and needs.pending ~= nil
        or sg and (sg:HasStateTag('busy') or sg:HasStateTag('working')
            or sg:HasStateTag('prechop') or sg:HasStateTag('premine'))
end
function Work:StopAction()
    local inst = self.inst
    inst:ClearBufferedAction()
    inst.components.locomotor:Stop()
    -- Mining/chopping states retain the old action after the main buffer clears.
    -- Finish an interruptible work animation so it cannot drive a stale action.
    if inst.sg and inst.sg:HasStateTag('working') and not inst.sg:HasStateTag('nointerrupt') then
        inst.sg:GoToState('idle')
    end
end
function Work:IsBusy() return self.core.job ~= nil and not self.core.job.blocked or self.returning ~= nil end
function Work:HasTask() return self.core.job~=nil end
function Work:OwnerValid(owner)
    local flower = self.inst.components.ybf_friend.flower
    return owner and owner:IsValid() and not owner:HasTag('playerghost')
        and owner.components.inventory and owner.components.trader
        and (not owner.components.health or not owner.components.health:IsDead())
        and flower and flower:IsValid() and flower.components.inventoryitem:GetGrandOwner() == owner
end
function Work:ValidTarget(target, job)
    if not job or not target or not target:IsValid() then return false end
    if job.step == 'craft' or job.step == 'equip' then return target == self.inst end
    if job.step == 'tech' then return Resources.InRange(self.inst,target,job.center,self.radius) and target.components.prototyper ~= nil end
    if job.step == 'give' then
        if target~=job.owner or not self:OwnerValid(target) then return false end
        if job.kind=='goal' then
            local x,_,z=target.Transform:GetWorldPosition()
            return (x-job.center.x)^2+(z-job.center.z)^2<=self.radius^2
        end
        return Resources.InRange(self.inst,target,job.center,self.radius)
    end
    if job.kind=='goal' and job.step=='pickup' then
        local c=target.components.inventoryitem
        return Resources.InRange(self.inst,target,job.center,self.radius) and target.prefab==job.collectitem and c and not c.owner and c.canbepickedup
    end
    return Resources.InRange(self.inst, target, job.center, self.radius)
        and Resources.Classify(target, job.collectitem or job.item, job.kind) == job.step
end
function Work:UsableTool(item, action)
    if not item or not item:IsValid() then return false end
    local c = item.components
    return c.equippable and c.equippable.equipslot == EQUIPSLOTS.HANDS
        and not c.equippable:IsRestricted(self.inst)
        and (not c.finiteuses or c.finiteuses:GetUses() > 0)
        and (not c.fueled or not c.fueled:IsEmpty())
        and c.tool and c.tool:CanDoAction(action) and c.tool:GetEffectiveness(action) > 0
end
function Work:Tool(action)
    local inv = self.inst.components.inventory
    local hand = inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    if self:UsableTool(hand, action) then return hand end
    for _, item in ipairs(Inventory.Items(self.inst, false)) do
        if self:UsableTool(item, action) then
            if hand and hand.components.equippable:ShouldPreventUnequipping() then
                return nil, '当前手持物品不能卸下'
            end
            if hand and not hand.components.inventoryitem.cangoincontainer then
                return nil, '当前手持物品无法保管，未自动丢弃'
            end
            local heavy = inv:GetEquippedItem(EQUIPSLOTS.BODY)
            if heavy and heavy:HasTag('heavy') then return nil, '正在搬运重物，不能装备工具' end
            -- Vanilla Equip swaps the owned tool out of its slot before storing
            -- the previous hand item. Do not move tools from another owner.
            inv:Equip(item)
            if inv:GetEquippedItem(EQUIPSLOTS.HANDS) == item then return item end
            return nil, '工具无法装备'
        end
    end
end
function Work:FindStep(job)
    local inst = self.inst
    if job.fatal then return nil, job.fatal, 'failed' end
    if job.kind=='goal' then return self.planner:Resolve(job) end
    if job.kind == 'craft' then
        job.collectitem=nil
        local info, reason = Crafting.Check(inst, job.item)
        if not info then
            if job.prepare then return self:PrepareCraft(job,reason) end
            return nil, reason, 'failed'
        end
        job.step = 'craft'; job.recipe = job.item; job.autotool = nil
        return inst
    elseif job.kind == 'equip' then
        local item=Inventory.Find(inst,job.item)
        local hand=inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
        if not item and hand and hand.prefab==job.item then item=hand end
        if not item and (job.item=='axe' or job.item=='pickaxe') then
            local action=job.item=='axe' and ACTIONS.CHOP or ACTIONS.MINE
            for _,owned in ipairs(Inventory.Items(inst,true)) do if self:UsableTool(owned,action) then item=owned;break end end
        end
        if not item then return nil,'没有持有'..Inventory.Label(job.item),'failed' end
        job.step='equip';job.invobject=item;job.label=item:GetDisplayName();return inst
    elseif job.kind == 'give' then
        if not self:OwnerValid(job.owner) then return nil, '玩家暂时无法接收；物品仍由我保管', 'failed' end
        if not Resources.InRange(inst, job.owner, job.center, self.radius) then
            return nil, '玩家不在本次附近范围内；物品仍由我保管', 'failed'
        end
        local item = self:GiftItem(job.item)
        if not item then return nil, '指定物品库存不足；已保留进度，继续其他可交付物品', 'exhausted' end
        if (job.failed[job.owner] or 0) >= 2 then return nil, '交付多次未成功或无法到达；剩余物品仍由我保管', 'failed' end
        job.step = 'give'; job.invobject = item
        return job.owner
    end
    local waitingloot = job.awaitloot_until and GetTime() < job.awaitloot_until
    local full, blocked = false, false
    local candidates = Resources.Scan(inst, job.center, self.radius, job.item, job.kind)
    if job.kind=='tree' then
        local trees={}
        local finished=(job.workdone or 0)>=job.goal
        for _,c in ipairs(candidates) do
            if (job.workdone or 0)>0 and c.step=='pickup' and inst:GetDistanceSqToInst(c.target)<=36
                or not finished and c.step=='chop' then trees[#trees+1]=c end
        end
        candidates=trees
        if finished and #candidates==0 and not waitingloot then
            job.treeclean=true;job.count=job.workdone
            return nil,'已砍倒指定棵数，实际掉落木头已检查并拾取','exhausted'
        end
    end
    -- Continue a partly worked source unless a requested drop is already available.
    if job.preferred then
        table.sort(candidates, function(a,b)
            if (a.step == 'pickup') ~= (b.step == 'pickup') then return a.step == 'pickup' end
            if (a.target == job.preferred) ~= (b.target == job.preferred) then return a.target == job.preferred end
            return inst:GetDistanceSqToInst(a.target) < inst:GetDistanceSqToInst(b.target)
        end)
    end
    for _, candidate in ipairs(candidates) do
        local target, step = candidate.target, candidate.step
        if waitingloot and step ~= 'pickup' then -- allow only actual requested drops during the fall
        elseif (job.failed[target] or 0) >= 2 then blocked = true
        elseif step == 'pickup' and inst.components.inventory:CanAcceptCount(target) < Inventory.Size(target) then full = true
        elseif step ~= 'pickup' and not Inventory.Room(inst, job.item, step == 'pick' and (target.components.pickable.numtoharvest or 1) or 1) then full = true
        else
            job.step = step; job.invobject = nil; job.autotool = nil
            if step == 'chop' or step == 'mine' then
                local action = step == 'chop' and ACTIONS.CHOP or ACTIONS.MINE
                local tool, reason = self:Tool(action)
                if reason then return nil, reason, 'failed' end
                if not tool then
                    local recipe = step == 'chop' and 'axe' or 'pickaxe'
                    local info, why = Crafting.Check(inst, recipe)
                    if not info then return nil, '缺少可用'..Inventory.Label(recipe)..'；'..why, 'failed' end
                    if (job.toolbuilds or 0) >= 8 then return nil, '工具更换次数达到本任务上限', 'failed' end
                    job.step = 'craft'; job.recipe = recipe; job.autotool = true; job.preferred = target
                    return inst
                end
                job.invobject = tool; job.preferred = target
            end
            return target
        end
    end
    if waitingloot and not full then return nil, nil, 'pending' end
    return nil, full and '背包空间不足，已保留持有物品' or blocked and '剩余目标多次失败或无法到达'
        or ('以我为中心'..self.radius..'世界单位内找不到可获取的'..job.label), full and 'full' or 'exhausted'
end
function Work:CanGive(job, item)
    local owner = job.owner
    if not self:OwnerValid(owner) or not owner.components.inventory:IsOpenedBy(owner) then
        return false, '玩家暂时无法接收；物品仍由我保管'
    end
    if owner.components.inventory:CanAcceptCount(item, 1) < 1 then
        return false, '玩家背包已满；剩余物品仍由我保管'
    end
    if owner.components.trader.deleteitemonaccept then return false, '接收规则会销毁物品，未交付' end
    local ok, reason = owner.components.trader:AbleToAccept(item, self.inst, 1)
    if ok and not owner.components.trader:WantsToAccept(item, self.inst, 1) then return false, '玩家拒绝这个物品；仍由我保管' end
    if not ok then return false, '玩家无法接收：'..tostring(reason or '拒绝')..'；物品仍由我保管' end
    return true
end
function Work:Guard(act)
    local job = self.core.job
    return job and job.serial == act.ybf_token and job.attempt == act.ybf_attempt
        and job.inflight and job.target == act.target and GetTime() < job.deadline
        and self.inst.components.ybf_friend.active and not self.inst.components.health:IsDead()
end
function Work:PushStep(target, token, attempt, done)
    local job = self.core.job
    local step = job.step
    local action = ({pickup=ACTIONS.YBF_GROUND_PICKUP, pick=ACTIONS.PICK, chop=ACTIONS.CHOP,
        mine=ACTIONS.MINE, craft=ACTIONS.YBF_CRAFT, give=ACTIONS.YBF_GIVE, equip=ACTIONS.YBF_EQUIP, tech=ACTIONS.YBF_TECH})[step]
    local act = BufferedAction(self.inst, target, action, job.invobject,
        step == 'craft' and self.inst:GetPosition() or nil, step == 'craft' and job.recipe or nil)
    act.ybf_token = token; act.ybf_attempt = attempt
    act.validfn = function()
        if not self:Guard(act) or job.fatal or not self:ValidTarget(target, job) then return false end
        if step == 'chop' or step == 'mine' then
            return self:UsableTool(act.invobject, action)
                and self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) == act.invobject
        elseif step == 'give' then
            if self:GiftItem(job.giveitem or job.item) ~= act.invobject then return false end
            return true
        end
        return true
    end
    local tracked=job.giveitem or job.collectitem or job.item
    local before = Inventory.Count(self.inst, tracked,step=='give')
    local workleft = target.components.workable and target.components.workable:GetWorkLeft() or nil
    local function finish(success)
        if not self:Guard(act) then return end
        -- A callback is only a signal to re-read actual world state.
        if step == 'give' then
            local lost,gained=0,0
            if act.ybf_give_before~=nil then
                lost=act.ybf_give_before-Inventory.Count(self.inst,tracked,true)
                gained=Inventory.Count(job.owner,tracked,true)-act.ybf_give_received
            end
            if lost > 0 and gained == lost and lost <= (job.kind=='goal' and job.givegoal or job.goal-job.count) then
                if job.kind=='goal' then self.planner:Gift(job,tracked,lost) else job.count = job.count + lost end
            else
                success = false
                if lost ~= 0 or gained ~= 0 then job.uncertain=true;job.fatal = '交付结果未能确认真实收发数量，停止以避免重复交付；已交付数量以库存为准' end
            end
        elseif step == 'tech' then
            success=success and self.inst:GetDistanceSqToInst(target)<=16
        elseif step == 'pick' then
            success = success and (Inventory.Count(self.inst, tracked) > before
                or not target:IsValid() or not target.components.pickable:CanBePicked())
        elseif step == 'chop' or step == 'mine' then
            success = success and (not target:IsValid() or not target.components.workable
                or target.components.workable:GetWorkAction() ~= action
                or target.components.workable:GetWorkLeft() < workleft)
            if success and (not target:IsValid() or not target.components.workable
                or not target.components.workable:CanBeWorked()
                or target.components.workable:GetWorkAction() ~= action) then
                if job.kind=='tree' then job.workdone=(job.workdone or 0)+1 end
                job.lootitem=tracked
                job.awaitloot_until = GetTime()+3 -- vanilla falling-tree loot may arrive after the hit callback
            end
        end
        if job.kind=='goal' then job.actions=(job.actions or 0)+1 end
        if success then job.failed[target] = nil end
        done(success)
    end
    Safety.Action(self,act)
    act:AddSuccessAction(function() Safety.Run(self,'action_success_'..step,function()finish(true)end) end)
    act:AddFailAction(function() Safety.Run(self,'action_failure_'..step,function()finish(false)end) end)
    if self.continuing==target and (step=='chop' or step=='mine') then
        act.options.no_predict_fastforward=true
        self.inst:PushBufferedAction(act)
    else self.inst.components.locomotor:PushAction(act, true) end
end
function Work:ContinueSwing(step)
    local job=self.core.job
    if not job or job.blocked or job.inflight or job.step~=step or job.fatal then return end
    if job.kind=='tree' and (job.workdone or 0)>=job.goal then return end
    if job.kind~='tree' and job.kind~='craft' and job.kind~='goal' and Inventory.Count(self.inst,job.item)>=job.goal then return end
    local t=job.preferred
    if not t or not self:ValidTarget(t,job) then return end
    local needs=self.inst.components.ybf_needs
    if needs then
        needs:Tick()
        if needs.pending or needs.explicit or needs.pause_requested then return end
    end
    self.continuing=t
    local ok,err=pcall(self.core.Tick,self.core,true)
    self.continuing=nil
    if not ok then self:ExecutionError(err) end
end
function Work:PerformTech(act)
    if not self:Guard(act) or self.inst:GetDistanceSqToInst(act.target)>16 then return false end
    local proto=act.target.components.prototyper
    if not proto or proto.CanUsePrototyper and not proto:CanUsePrototyper(self.inst) then return false end
    local builder=self.inst.components.builder
    builder:EvaluateTechTrees()
    local recipe=GetValidRecipe(self.core.job.techrecipe or self.core.job.item)
    if builder:KnowsRecipe(recipe) or CanPrototypeRecipe(recipe.level,builder.accessible_tech_trees) then return true end
    return false
end
function Work:GiftItem(prefab)
    for _,item in ipairs(Inventory.Items(self.inst,true)) do if item.prefab==prefab then return item end end
end
function Work:PerformGive(act)
    if not self:Guard(act) or self.inst:GetDistanceSqToInst(act.target)>16 then return false end
    local job=self.core.job
    local ok,reason=self:CanGive(job,act.invobject)
    if not ok then job.fatal=reason;return false end
    local remaining=job.kind=="goal" and job.givegoal or job.goal-job.count
    local count=math.min(remaining,Inventory.Size(act.invobject),job.owner.components.inventory:CanAcceptCount(act.invobject))
    if count<1 then job.fatal='尝试交付失败：玩家无法接收，剩余物品由我保管';return false end
    local trader=job.owner.components.trader
    local can,why=trader:AbleToAccept(act.invobject,self.inst,count)
    if not can or not trader:WantsToAccept(act.invobject,self.inst,count) then
        job.fatal='尝试交付失败：'..tostring(why or '玩家拒绝');return false
    end
    local tracked=job.giveitem or job.item
    act.ybf_give_before=Inventory.Count(self.inst,tracked,true)
    act.ybf_give_received=Inventory.Count(job.owner,tracked,true)
    return trader:AcceptGift(self.inst,act.invobject,count)
end
function Work:PerformEquip(act)
    if not self:Guard(act) then return false end
    local inv=self.inst.components.inventory
    local item=act.invobject
    if not item or not item:IsValid() or (item.components.finiteuses and item.components.finiteuses:GetUses()<=0) or (item.components.fueled and item.components.fueled:IsEmpty()) or not item.components.equippable or item.components.equippable:IsRestricted(self.inst) then
        self.core.job.fatal='这个物品不能装备';return false
    end
    local hand=inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    if hand and (hand.components.equippable:ShouldPreventUnequipping() or not hand.components.inventoryitem.cangoincontainer) then
        self.core.job.fatal='当前手持物品无法安全卸下';return false
    end
    local heavy=inv:GetEquippedItem(EQUIPSLOTS.BODY)
    if heavy and heavy:HasTag('heavy') then self.core.job.fatal='正在搬运重物，无法装备';return false end
    inv:Equip(item)
    local ok=inv:GetEquippedItem(item.components.equippable.equipslot)==item
    if ok then self.core.job.count=1 end
    return ok
end
-- Bounded one-level ingredients and an existing nearby research station.
function Work:PrepareCraft(job,reason)
    local recipe=GetValidRecipe and GetValidRecipe(job.item) or AllRecipes[job.item]
    if not recipe or not Crafting.allowed[job.item] then return nil,reason,'failed' end
    local builder=self.inst.components.builder
    if not builder or not builder:CanLearn(job.item) then return nil,reason,'failed' end
    for _,ingredient in ipairs(recipe.ingredients) do
        local required=math.max(1,RoundBiasedUp(ingredient.amount*builder.ingredientmod))
        if Inventory.Count(self.inst,ingredient.type)<required then
            if not labels[ingredient.type] then return nil,'缺少'..Inventory.Label(ingredient.type)..'，暂不支持递归制作材料','failed' end
            local child=job.material
            if not child or child.item~=ingredient.type then
                child={kind='collect',item=ingredient.type,label=labels[ingredient.type],goal=required,center=job.center,failed=job.failed}
                job.material=child
            end
            child.awaitloot_until=job.awaitloot_until
            local target,why,code=self:FindStep(child)
            for _,k in ipairs({'step','invobject','autotool','recipe','preferred'}) do job[k]=child[k] end
            job.collectitem=ingredient.type
            return target,why,code=='exhausted' and 'failed' or code
        end
    end
    job.collectitem=nil;job.material=nil
    builder:EvaluateTechTrees()
    if builder:KnowsRecipe(recipe) or CanPrototypeRecipe(recipe.level,builder.accessible_tech_trees) then return nil,reason,'failed' end
    local x,y,z=self.inst.Transform:GetWorldPosition()
    local stations=TheSim:FindEntities(x,y,z,self.radius,nil,{'INLIMBO'})
    table.sort(stations,function(a,b)return self.inst:GetDistanceSqToInst(a)<self.inst:GetDistanceSqToInst(b) end)
    for _,target in ipairs(stations) do
        local proto=target.components.prototyper
        if proto and (not proto.restrictedtag or self.inst:HasTag(proto.restrictedtag))
            and Resources.InRange(self.inst,target,job.center,self.radius) and CanPrototypeRecipe(recipe.level,proto.trees)
            and (job.failed[target] or 0)<2 then
            job.step='tech';job.invobject=nil;return target
        end
    end
    return nil,'附近没有可解锁这个配方的科技站；'..reason,'failed'
end
function Work:RequestPlan(entries,owner)
    if type(entries)~='table' or #entries<1 or #entries>12 then return false,'计划须有1至12个步骤' end
    local plan={}
    for _,e in ipairs(entries) do
        if type(e)~='table' then return false,'计划步骤必须为表' end
        local kind,item,n=e.kind,e.item,e.quantity
        if kind~='collect' and kind~='craft' and kind~='give' and kind~='tree' and kind~='equip' then return false,'计划步骤无效' end
        if type(item)~='string' or not item:match('^[%w_]+$') or #item>80 or type(n)~='number' or n%1~=0 or n<1 or n>100 then return false,'计划物品或数量无效' end
        if (kind=='collect' and not labels[item]) or (kind=='craft' and not Crafting.allowed[item]) or (kind=='tree' and item~='log') or item=='ybf_friendship_flower' then return false,'不支持计划物品' end
        if e.prepare~=nil and type(e.prepare)~='boolean' or e.ensure~=nil and (kind~='craft' or type(e.ensure)~='boolean') then return false,'制作计划标志无效' end
        if kind=='equip' and n~=1 then return false,'一次装备一个物品' end
        if kind=='give' and not self:OwnerValid(owner) then return false,'交付对象无效' end
        plan[#plan+1]={kind=kind,item=item,goal=kind=='equip' and 1 or n,label=kind=='tree' and '树' or labels[item] or Inventory.Label(item),prepare=e.prepare==true,ensure=e.ensure==true}
    end
    self.core:Start(plan[1].item,plan[1].goal,plan[1].label,plan)
    local j=self.core.job;j.kind=plan[1].kind;j.prepare=plan[1].prepare;j.ensure=plan[1].ensure;j.owner=owner
    return true,nil,j.id
end
function Work:PerformCraft(act)
    if not self:Guard(act) then return false end
    local job = self.core.job
    local info, reason = Crafting.Check(self.inst, act.recipe)
    if not info then job.fatal = reason; return false end
    local ok, gained, consumed, why = Crafting.Perform(self.inst, act.recipe, info, act)
    job.audit = {recipe=act.recipe, output=gained, consumed=consumed}
    if job.autotool then job.toolbuilds = (job.toolbuilds or 0) + 1
    elseif job.kind~='goal' then job.count = job.count + gained end
    if not ok then job.uncertain=true;job.fatal = '制作未能确认实际产出与材料消耗；停止避免重复制作：'..tostring(why or '库存结果不匹配') end
    return ok
end
function Work:PerformPickup(act)
    if not self:Guard(act) then return false end
    local job, item = self.core.job, act.target
    if not self:ValidTarget(item, job) then return false end
    local inv = self.inst.components.inventory
    if inv:CanAcceptCount(item) < Inventory.Size(item) then return false end
    local tracked=job.giveitem or job.collectitem or job.item
    local before = Inventory.Count(self.inst, tracked)
    local ok = ACTIONS.PICKUP.fn(act)
    local after=Inventory.Count(self.inst,tracked)
    if job.kind~='craft' and job.kind~='tree' and job.kind~='goal' then job.count=after end
    return ok and after > before
end
-- Stable planner entry point. Quantities are final owned resource totals for
-- collect/pickup, newly crafted output units for craft, exact transferred units for give.
-- Goal API: targets are owned-output quantities, not model-specified action steps.
function Work:RequestGoal(targets,deliver,owner)
    if type(targets)~='table' or #targets<1 or #targets>3 or type(deliver)~='boolean' then return false,'目标数据无效' end
    if deliver and not self:OwnerValid(owner) then return false,'交付对象无效' end
    local clean,seen,total={}, {},0
    for _,target in ipairs(targets) do
        if type(target)~='table' then return false,'目标条目无效' end
        local item,n=target.item,target.quantity
        if type(item)~='string' or #item>80 or not item:match('^[a-z0-9_]+$') or item=='ybf_friendship_flower' or seen[item]
            or type(n)~='number' or n%1~=0 or n<1 or n>100 then return false,'目标物品或数量无效' end
        clean[#clean+1]={item=item,quantity=n};seen[item]=true;total=total+n
    end
    self.core:Start(clean[1].item,total,Inventory.Label(clean[1].item))
    local j=self.core.job;j.kind='goal';j.targets=clean;j.deliver=deliver;j.owner=owner
    j.given={};j.resource_states={};j.trace={};j.actions=0;j.resumes=0
    j.deadline=GetTime()+self.timeout*2
    self.planner:Refresh(j)
    return true,nil,j.id
end
function Work:BlockGoal(job,reason,code)
    if self.core.job~=job or job.blocked then return end
    job.attempt=(job.attempt or 0)+1;job.inflight=false
    self:StopAction();self.planner:Refresh(job)
    job.blocked={reason=reason,code=code or 'unavailable',time=GetTime()}
    job.nonresumable=job.uncertain or code=='unverified_result'
    local text='[游戏执行受阻] '..self.planner:Feedback(job,reason)
        ..(job.nonresumable and '；结果未确认，请检查库存后停止并重新下达目标。' or '；已保留物资和任务进度，可说“继续任务”。')
    self.last_report=text
    self:Announce(text)
    self:Restore(job.previous,job.anchor)
end
function Work:ResumeGoal()
    local j=self.core.job
    if not j or j.kind~='goal' or not j.blocked then return false,'没有可恢复的受阻目标任务' end
    if j.nonresumable then return false,'结果未确认，需要检查库存后停止并重新下达目标' end
    if (j.resumes or 0)>=GoalPlanner.MAX_RESUMES then return false,'本任务恢复次数达到上限，物资保留；请重新下达目标' end
    j.resumes=(j.resumes or 0)+1;j.blocked=nil;j.fatal=nil;j.failed={}
    j.deadline=GetTime()+self.timeout*2;j.settle_until=nil
    self.core.sequence=self.core.sequence+1;j.serial=self.core.sequence;j.attempt=(j.attempt or 0)+1
    self.returning=nil;self:StopAction()
    self.inst.components.ybf_friend.mode='work';self.inst.components.ybf_friend:ApplyMovementPolicy()
    self.planner:Refresh(j)
    return true,nil,j.id
end
function Work:Request(kind, item, quantity, owner)
    if kind ~= 'pickup' and kind ~= 'collect' and kind ~= 'craft' and kind ~= 'give' then return false, '工作类型无效' end
    if type(item) ~= 'string' or #item > 80 or not item:match('^[%w_]+$') then return false, '物品标识无效' end
    if quantity ~= nil and (type(quantity) ~= 'number' or quantity % 1 ~= 0 or quantity < 1 or quantity > 100) then return false, '数量须为1至100整数' end
    if kind ~= 'pickup' and quantity == nil then return false, '请说明需要的数量' end
    if (kind == 'pickup' or kind == 'collect') and not labels[item] then return false, '暂不支持这个资源' end
    if kind == 'craft' and not Crafting.allowed[item] then return false, '本阶段支持斧头、鹤嘴锄、石砖、木板、绳子和火把' end
    if kind == 'give' and (item == 'ybf_friendship_flower' or not self:OwnerValid(owner)) then return false, '交付对象或物品无效' end
    self.core:Start(item, quantity, labels[item] or Inventory.Label(item))
    local job = self.core.job
    job.kind = kind; job.owner = owner
    if kind == 'pickup' or kind == 'collect' then job.count = Inventory.Count(self.inst, item) end
    return true, nil, job.id
end
function Work:Status(task_id)
    local job = self.core.job
    if job and (not task_id or job.id == task_id) then
        return {task_id=job.id,status=job.blocked and "blocked" or "running",blocked=job.blocked,targets=job.targets,delivered=job.given,dependencies=job.trace,kind=job.kind,item=job.item,quantity=job.goal,
            count=job.count,phase=job.step,step_index=job.index,plan=job.plan,paused=self.inst.components.ybf_needs and self.inst.components.ybf_needs.pending ~= nil}
    end
    if self.last_result and (not task_id or self.last_result.task_id == task_id) then
        return {status="finished",result=self.last_result,plan_result=self.last_plan_result,summary=self.last_report}
    end
    return {status="unknown"} -- bounded: only the most recent result is retained
end
function Work:Start(item, goal)
    if type(item) ~= 'table' then return self:Request('pickup', item, goal) end
    if goal ~= nil or #item < 1 or #item > 3 then return false end
    local plan, seen = {}, {}
    for _, entry in ipairs(item) do
        local n = entry.quantity
        if not labels[entry.item] or seen[entry.item] or n ~= nil and (type(n) ~= 'number' or n%1 ~= 0 or n<1 or n>100) then return false end
        seen[entry.item] = true
        plan[#plan+1] = {item=entry.item, goal=n, label=labels[entry.item]}
    end
    self.core:Start(plan[1].item, plan[1].goal, plan[1].label, plan)
    self.core.job.kind = 'pickup'
    self.core.job.count = Inventory.Count(self.inst, plan[1].item)
    return true
end
function Work:Restore(mode, anchor)
    if mode == 'wait' then
        if not anchor then self.inst.components.ybf_friend:SetMode('wait'); return end
        self.returning = {anchor=anchor, deadline=GetTime()+8}
        self.inst.components.ybf_friend.mode = 'work'
        self.inst.components.ybf_friend:ApplyMovementPolicy()
        self.inst.components.locomotor:GoToPoint(Vector3(anchor.x,anchor.y,anchor.z))
    else self.inst.components.ybf_friend:SetMode('follow') end
end
function Work:TickUnsafe()
    local inst = self.inst
    if not inst.components.ybf_friend.active then return end
    if inst.components.health:IsDead() then self:Cancel(false); return end
    local j=self.core.job
    local before=inst.components.ybf_needs and inst.components.ybf_needs.pending
    if inst.components.ybf_needs then inst.components.ybf_needs:Tick() end
    local now=GetTime();local elapsed=self.last_tick and math.min(1,math.max(0,now-self.last_tick)) or 0;self.last_tick=now
    if j and j.kind=='goal' and not j.blocked and (before or inst.components.ybf_needs and inst.components.ybf_needs.pending) then
        local extra=math.min(elapsed,math.max(0,60-(j.supply_pause or 0)))
        j.supply_pause=(j.supply_pause or 0)+extra;j.deadline=j.deadline+extra
    end
    self.core:Tick()
    local r = self.returning
    if r then
        local p, a = self:Position(), r.anchor
        if (p.x-a.x)^2 + (p.z-a.z)^2 <= 1 then
            self.returning = nil
            inst.components.ybf_friend:SetMode('wait')
            inst.components.ybf_friend.wait_position = a
        elseif GetTime() >= r.deadline then
            self.returning = nil
            inst.components.ybf_friend:SetMode('wait')
            self:Announce('无法返回原等待位置，已在当前位置停止。')
        end
    end
end
function Work:ExecutionError(err)
    local j=self.core.job
    print('[YBF WORK] execution_error task='..tostring(j and j.id)..' step='..tostring(j and j.step)..' target='..tostring(j and j.target and j.target.prefab)..': '..tostring(err))
    if self.core.job then
        if self.core.job.kind=='goal' then self.core.job.uncertain=true;self:BlockGoal(self.core.job,'工作执行出现异常；详情见服务器日志 [YBF WORK]','unverified_result')
        else self.core:End('工作执行出现异常，已停止；详情见服务器日志 [YBF WORK]',true) end
    end
end
function Work:Tick()
    local ok,err=pcall(self.TickUnsafe,self)
    if not ok then self:ExecutionError(err) end
end
function Work:Cancel(restore)
    local returning = self.returning
    self.returning = nil
    -- Invalidate before interrupting the action: ClearBufferedAction can call Fail.
    local job = self.core.job
    if job then job.attempt = (job.attempt or 0) + 1 end
    self:StopAction()
    if returning and restore then self:Restore('wait', returning.anchor) end
    self.core:End('任务已停止', restore)
end
function Work:Snapshot()
    local job = self.core.job
    local visible = {}
    local center = job and job.center or self:Position()
    for prefab in pairs(labels) do
        for _, candidate in ipairs(Resources.Scan(self.inst, center, self.radius, prefab, 'collect')) do
            if #visible < 24 then visible[#visible+1] = {prefab=candidate.target.prefab, resource=prefab,
                action=candidate.step, tool=candidate.step == 'chop' and 'axe' or candidate.step == 'mine' and 'pickaxe' or nil} end
        end
    end
    return {version='0.12.1',capabilities={'goal','bounded_dependencies','resume','verified_delivery'},radius=self.radius, center='朋友当前位置，且限制在本次起点范围', nearby=visible,
        task=job and {status=job.blocked and "blocked" or "running",blocked=job.blocked,targets=job.targets,delivered=job.given,dependencies=job.trace,kind=job.kind,item=job.item,quantity=job.goal,count=job.count,phase=job.step,step_index=job.index,plan=job.plan} or nil,
        last_result=self.last_result,last_summary=self.last_report,last_plan_result=self.last_plan_result, recipes={'axe','pickaxe','cutstone','boards','rope','torch'}}
end
function Work:OnRemoveFromEntity()
    self:Cancel(false)
    if self.tick then self.tick:Cancel() end
end
return Work
