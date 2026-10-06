local assets = {
    Asset("ANIM", "anim/flower_petals.zip"),
    Asset("INV_IMAGE", "petals"),
}
local prefabs = { "wilson", "skeleton_player" }

local function SetName(inst, text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" then text = "威尔逊朋友" end
    inst._ybf_name = text
    if inst._ybf_friend and inst._ybf_friend:IsValid() then
        inst._ybf_friend.components.ybf_friend:SetName(text)
    end
end

local function Bind(inst, friend)
    inst._ybf_friend = friend
    inst._ybf_created = true
    friend.components.ybf_friend:Activate(inst, inst._ybf_name)
    friend.components.ybf_friend:Bind(inst)
end

local function EnsureFriend(inst, owner)
    if inst._ybf_created or inst._ybf_dead or inst._ybf_friend then return end
    owner = inst.components.inventoryitem:GetGrandOwner() or owner
    if not owner or not owner:HasTag("player") or owner:HasTag("ybf_friend") then return end
    local friend = SpawnPrefab("wilson")
    if not friend then return end
    local pos = owner:GetPosition()
    -- 在持有者附近的可行走地面生成，再通过切斯特 Follow 走近。
    local offset = FindWalkableOffset(pos, math.random() * TWOPI, 12, 12, true)
    if offset then pos = pos + offset end
    friend.Physics:Teleport(pos:Get())
    Bind(inst, friend)
end

local function OnPutInInventory(inst, owner)
    if inst._ybf_puttask then inst._ybf_puttask:Cancel() end
    inst._ybf_puttask = inst:DoTaskInTime(0, function()
        inst._ybf_puttask = nil
        EnsureFriend(inst, owner)
    end)
end

local function OnBuilt(inst, data)
    local builder = data and data.builder
    if builder then
        EnsureFriend(inst, builder)
        -- 等待制作物品的网络实体同步后再开始；组件自动启动时先结束旧会话。
        inst:DoTaskInTime(0.5, function()
            if builder:IsValid() and inst.components.writeable then
                inst.components.writeable:EndWriting()
                inst.components.writeable:BeginWriting(builder)
            end
        end)
    end
end

local function FriendDied(inst, friend)
    if inst._ybf_friend == friend then
        inst._ybf_dead = true
        inst._ybf_friend = nil
    end
end

local function Farewell(inst, doer)
    -- 使用原版拆包相同的 build_pre/loop/pst 动画，完成操作才调用这里。
    local friend = inst._ybf_friend
    if friend and friend:IsValid() then friend.components.ybf_friend:Farewell() end
    inst._ybf_dead = true
    inst:Remove()
end

local function OnSave(inst, data)
    data.created = inst._ybf_created
    data.dead = inst._ybf_dead
    data.friendname = inst._ybf_name
    local friend = inst._ybf_friend
    if friend and friend:IsValid() and not friend.components.health:IsDead() then
        data.friend = friend:GetSaveRecord()
        if data.friend.data and data.friend.data.ybf_friend and data.friend.data.ybf_friend.mode=="wait" then
            data.wait_world=TheWorld:HasTag("cave") and "cave" or "surface"
        end
    elseif inst._ybf_waitrecord then
        data.friend=inst._ybf_waitrecord
        data.wait_world=inst._ybf_waitworld
    end
end

local function OnLoad(inst, data)
    if not data then return end
    inst._ybf_created = data.created or false
    inst._ybf_dead = data.dead or false
    SetName(inst, data.friendname)
    if data.friend and not inst._ybf_dead then
        local currentworld=TheWorld:HasTag("cave") and "cave" or "surface"
        if data.wait_world and data.wait_world~=currentworld then
            -- Keep a dormant record instead of spawning at an unrelated shard's coordinates.
            inst._ybf_waitrecord=data.friend;inst._ybf_waitworld=data.wait_world
            return
        end
        local friend = SpawnSaveRecord(data.friend)
        if friend then Bind(inst, friend) end
    end
end

local function OnRemove(inst)
    if inst._ybf_puttask then inst._ybf_puttask:Cancel() end
    local friend = inst._ybf_friend
    -- 保存/洞穴迁移会移除源端的花：其朋友记录随花保存，源实体一并清理。
    if friend and friend:IsValid() and not friend.components.health:IsDead() then
        friend:Remove()
    end
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)
    inst.AnimState:SetBank("petals")
    inst.AnimState:SetBuild("flower_petals")
    inst.AnimState:PlayAnimation("anim")
    inst.pickupsound = "vegetation_grassy"
    inst:AddTag("ybf_friendship_flower")
    inst:AddTag("nobundling")
    MakeInventoryFloatable(inst, "small", 0.1, 0.6)
    inst:AddTag("_writeable")
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst:RemoveTag("_writeable")
    inst._ybf_name = "威尔逊朋友"
    inst._ybf_created = false
    inst._ybf_dead = false
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("petals")
    inst.components.inventoryitem:SetOnPutInInventoryFn(OnPutInInventory)
    inst:AddComponent("inspectable")
    inst.components.inspectable.getspecialdescription = function()
        return "这朵友谊小花属于" .. inst._ybf_name .. "。"
    end
    inst:AddComponent("leader")
    -- 朋友嵌入花的完整记录；禁止 leader 再保存外部 GUID 引用。
    inst.components.leader.OnSave = function() return nil end
    inst.components.leader.LoadPostPass = function() end
    inst:AddComponent("writeable")
    inst.components.writeable:SetDefaultWriteable(true)
    inst.components.writeable:SetAutomaticDescriptionEnabled(false)
    inst.components.inspectable.getspecialdescription = function()
        return "这朵友谊小花属于" .. inst._ybf_name .. "。"
    end
    inst.components.writeable:SetOnWrittenFn(function(_, text) SetName(inst, text) end)
    inst:AddComponent("migrationpetowner")
    inst.components.migrationpetowner:SetPetFn(function()
        local f=inst._ybf_friend
        return f and f.components.ybf_friend:AllowsOwnerMovement() and f or nil
    end)
    inst.YBFFarewell = Farewell
    inst.YBFOnFriendDied = FriendDied
    inst.OnSave = OnSave
    inst.OnLoad = OnLoad
    inst.OnRemoveEntity = OnRemove
    inst:ListenForEvent("onbuilt", OnBuilt)
    -- 原版 builder 对物品调用 OnBuilt，只有建筑才发 onbuilt 事件。
    inst.OnBuiltFn = function(item, builder) OnBuilt(item, { builder = builder }) end
    -- 不添加 stackable、perishable、edible：不堆叠、不腐烂、不能误吃。
    return inst
end
return Prefab("ybf_friendship_flower", fn, assets, prefabs)
