local Alerts = require("ybf_alerts")
local FriendBrain = require("brains/ybf_friendbrain")
local PlayerExtensions = require("prefabs/player_common_extensions")

local function Value(inst, key)
    local c = inst.components[key]
    if key == "hunger" then return c.current end
    if key == "sanity" then return c.current end
    return c.currenthealth
end
local Friend = Class(function(self, inst)
    self.inst = inst
    self.mode = "follow"
    self.active = false
    self.name = "威尔逊朋友"
    self.alerts = {}
    self.lastvalues = {}
end)

function Friend:SetName(name)
    self.name = name or self.name
    if self.inst.components.named then self.inst.components.named:SetName(self.name) end
end

function Friend:CheckAlert(key)
    if self.inst.components.ybf_needs then return end -- Consolidated local needs/help policy.
    if not self.active or self.finished or self.dead
        or not self.inst:IsValid() or self.inst.components.health:IsDead() then return end
    local value = Value(self.inst, key)
    if self.lastvalues[key] == value then return end
    self.lastvalues[key] = value
    self.alerts[key] = self.alerts[key] or Alerts.Initial(key, value)
    local text = Alerts.Step(key, self.alerts[key], value)
    if text then
        -- 朋友没有真人账号；带朋友名字的消息发到公共聊天记录。
        local line = "[" .. self.name .. "] " .. text
        self.inst:YBFAnnounce(line)
    end
end

function Friend:Activate(flower, name)
    if flower then self.flower = flower end
    if name then self.name = name end
    if self.active then self:SetName(self.name); return end
    self.active = true
    if not self.inst.components.ybf_work then self.inst:AddComponent("ybf_work") end
    if not self.inst.components.ybf_needs then self.inst:AddComponent("ybf_needs") end
    self.inst.components.eater.eatwholestack=false
    local inst = self.inst
    inst:AddTag("ybf_friend")
    -- 实体仅由花的存档保存，避免世界存一份、花里又存一份造成复制。
    inst.persists = false
    if not inst.components.named then inst:AddComponent("named") end
    if not inst.components.follower then inst:AddComponent("follower") end
    inst.components.follower.canaccepttarget = false
    inst.components.follower:KeepLeaderOnAttacked()
    inst.components.follower.keepdeadleader = true
    local follower=inst.components.follower
    local setleader=follower.SetLeader
    follower.SetLeader=function(c, leader)
        return setleader(c, self:AllowsOwnerMovement() and leader or nil)
    end
    local startleash=follower.StartLeashing
    follower.StartLeashing=function(c)
        if self:AllowsOwnerMovement() then return startleash(c) end
        c:StopLeashing()
    end
    self:ApplyMovementPolicy()
    self:SetName(self.name)
    -- 原版给予玩家动作要求目标的 inventory 为打开状态。
    inst.components.inventory:Open()

    -- 保留原版数值和生存组件，只取消真人输入。移动由 Brain 驱动。
    if inst.components.playercontroller then inst.components.playercontroller:Enable(false) end
    -- 朋友不是可复活的真人；死亡动画完成后改走模组的骨架/移除流程。
    inst:RemoveEventCallback("death", PlayerExtensions.OnPlayerDeath)
    if inst.components.revivablecorpse then inst:RemoveComponent("revivablecorpse") end
    inst.ghostenabled = false
    inst:ListenForEvent("death", function(_, data)
        self:StopLivingTasks()
        inst.deathcause = (data and data.cause) or (self.farewell and "ybf_farewell") or "unknown"
        if inst.brain then inst.brain:Stop() end
        if self.flower and self.flower:IsValid() then self.flower:YBFOnFriendDied(inst) end
    end)
    for _, key in ipairs({ "hunger", "sanity", "health" }) do
        local k = key
        self.alerts[k] = self.alerts[k] or Alerts.Initial(k, Value(inst, k))
        self.lastvalues[k] = Value(inst, k)
        inst:ListenForEvent(k .. "delta", function(source)
            if source == inst then self:CheckAlert(k) end
        end, inst)
    end
    self.livingtask = inst:DoPeriodicTask(0.5, function()
        if self.dead or inst.components.health:IsDead() then self:StopLivingTasks(); return end
        for _, key in ipairs({ "hunger", "sanity", "health" }) do self:CheckAlert(key) end
        self:TryEat()
    end)
    inst:SetBrain(FriendBrain)
    inst:RestartBrain()
    -- 使检查朋友时说名字；悬停名字由 named 副本同步。
    inst.components.inspectable.getspecialdescription = function() return "这是" .. self.name .. "。" end
end

function Friend:Bind(flower)
    self.flower = flower
    self:ApplyMovementPolicy()
    self:SetName(flower._ybf_name)
end

-- Single movement policy shared by brain, follower and migration adapter.
function Friend:AllowsOwnerMovement()
    return self.mode == "follow"
end
function Friend:ApplyMovementPolicy()
    local c=self.inst.components.follower
    if not c then return end
    if not self:AllowsOwnerMovement() then
        c:StopLeashing()
        if c.porttask then c.porttask:Cancel();c.porttask=nil end
        c.noleashing=true
        c:SetLeader(nil)
        c:ClearCachedPlayerLeader()
    else
        c.noleashing=false
        c:SetLeader(self.flower)
        c:StartLeashing()
    end
end
function Friend:SetMode(mode)
    if mode~="wait" and mode~="follow" then return false,"未知行为模式" end
    if not self.active or self.dead or self.finished or self.inst.components.health:IsDead() then return false,"朋友无法行动" end
    if mode=="wait" then
        local x,y,z=self.inst.Transform:GetWorldPosition()
        self.wait_position={x=x,y=y,z=z}
    else self.wait_position=nil end
    self.mode=mode
    self:ApplyMovementPolicy()
    -- Preserve eating and its buffered action; stop only locomotion.
    if self.inst.components.locomotor then self.inst.components.locomotor:Stop() end
    if self.inst.brain then self.inst.brain:Stop();self.inst:RestartBrain() end
    print("[YBF MODE] mode="..mode.." position="..tostring(self.wait_position and self.wait_position.x)..","..tostring(self.wait_position and self.wait_position.z))
    return true
end

-- Preserve the old periodic entry point; the new local policy owns consumption.
function Friend:TryEat()
    if self.inst.components.ybf_needs then self.inst.components.ybf_needs:Tick() end
end

function Friend:StopLivingTasks()
    if self.inst.components.ybf_needs then self.inst.components.ybf_needs:Stop() end
    self.dead = true
    self.inst:AddTag("ybf_dead")
    if self.livingtask then self.livingtask:Cancel(); self.livingtask = nil end
    self.inst:ClearBufferedAction()
end

function Friend:OnRemoveFromEntity()
    if self.livingtask then self.livingtask:Cancel(); self.livingtask = nil end
end

function Friend:Farewell()
    if self.inst.components.health:IsDead() then return end
    self:StopLivingTasks()
    self.farewell = true
    self.inst.deathcause = "ybf_farewell"
    self.inst.components.health:Kill()
end

function Friend:FinishDeath()
    if self.finished then return end
    self:StopLivingTasks()
    self.finished = true
    local inst = self.inst
    -- SGwilson 的原版 death 状态已经播放死亡动画并掉落背包和装备。
    inst.components.inventory:DropEverything(true)
    local x, y, z = inst.Transform:GetWorldPosition()
    if TheWorld.Map:IsPassableAtPoint(x, y, z) then
        local skel = SpawnPrefab("skeleton_player")
        if skel then
            skel.Transform:SetPosition(x, y, z)
            if skel.SetSkeletonDescription then
                skel:SetSkeletonDescription("wilson", self.name, inst.deathcause or "unknown", nil, nil)
            end
        end
    end
    if self.flower and self.flower:IsValid() then self.flower:YBFOnFriendDied(inst) end
    inst:DoTaskInTime(0, inst.Remove)
end

function Friend:OnSave()
    if not self.active then return nil end
    local flags = {}
    for key, state in pairs(self.alerts) do
        flags[key] = { normal = state.normal, urgent = state.urgent }
    end
    return { active = true, name = self.name, alerts = flags, needs=self.inst.components.ybf_needs and self.inst.components.ybf_needs:SaveState(), mode=(self.mode=="work" and ((self.inst.components.ybf_work.core.job and self.inst.components.ybf_work.core.job.previous) or (self.inst.components.ybf_work.returning and "wait") or "follow") or self.mode), wait_position=(self.mode=="work" and ((self.inst.components.ybf_work.core.job and self.inst.components.ybf_work.core.job.anchor) or (self.inst.components.ybf_work.returning and self.inst.components.ybf_work.returning.anchor)) or self.wait_position) }
end
function Friend:OnLoad(data)
    if data and data.active then
        self.mode=data.mode=="wait" and "wait" or "follow"
        self.wait_position=data.wait_position
        self.name = data.name or self.name
        self.alerts = {}
        for key, state in pairs(data.alerts or {}) do
            self.alerts[key] = { normal = state.normal == true, urgent = state.urgent == true }
        end
        self:Activate(nil, self.name)
        if self.inst.components.ybf_needs then self.inst.components.ybf_needs:LoadState(data.needs) end
    end
end
return Friend
