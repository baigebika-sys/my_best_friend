-- Perception is local to the friend and additionally bounded by the job origin.
local M = {}
M.labels = {twigs='树枝', cutgrass='草', log='木头', rocks='石头', flint='燧石', goldnugget='金块'}
local trees = {evergreen=true, evergreen_sparse=true, deciduoustree=true, twiggytree=true}
local function hasloot(dropper, prefab)
    if not dropper then return false end
    for _, value in ipairs(dropper.loot or {}) do if value == prefab then return true end end
    for _, value in ipairs(dropper.chanceloot or {}) do
        if value.prefab == prefab and (value.chance or 0) > 0 then return true end
    end
    for _, value in ipairs(dropper.randomloot or {}) do
        if value.prefab == prefab and (value.weight or 0) > 0 and (dropper.numrandomloot or 0) > 0 then return true end
    end
    local shared = LootTables and LootTables[dropper.chanceloottable]
    for _, value in ipairs(shared or {}) do
        if value[1] == prefab and (value[2] or 0) > 0 then return true end
    end
    return false -- Unknown custom loot functions are not evidence of a resource.
end
function M.Safe(target)
    return target and target:IsValid() and not target:IsInLimbo()
        and not target:HasTag('irreplaceable') and not target:HasTag('NOCLICK')
        and not target:HasTag('fire')
        and not (target.components.burnable and target.components.burnable:IsBurning())
end
function M.InRange(inst, target, center, radius)
    if not M.Safe(target) then return false end
    local x, _, z = target.Transform:GetWorldPosition()
    return (x-center.x)^2 + (z-center.z)^2 <= radius^2
        and inst:GetDistanceSqToInst(target) <= radius^2
end
function M.Classify(target, prefab, kind)
    if not M.Safe(target) or not M.labels[prefab] then return nil end
    local c = target.components
    if target.prefab == prefab and c.inventoryitem and not c.inventoryitem.owner
        and c.inventoryitem.canbepickedup then return 'pickup' end
    if kind == 'pickup' then return nil end
    if (prefab == 'twigs' and target.prefab == 'sapling'
        or prefab == 'cutgrass' and target.prefab == 'grass')
        and c.pickable and c.pickable.product == prefab and c.pickable:CanBePicked()
        and not (c.pickable.IsStuck and c.pickable:IsStuck()) then return 'pick' end
    local workable = c.workable
    if not workable or not workable:CanBeWorked() then return nil end
    local action = workable:GetWorkAction()
    if prefab == 'log' and trees[target.prefab] and target:HasTag('tree')
        and not target:HasTag('stump') and not target:HasTag('monster') and not target.monster
        and not target.monster_start_task and not target.dostartmonster_task and not target:HasTag('burnt')
        and action == ACTIONS.CHOP then return 'chop' end
    if (prefab == 'rocks' or prefab == 'flint' or prefab == 'goldnugget')
        and action == ACTIONS.MINE and hasloot(c.lootdropper, prefab) then return 'mine' end
end
function M.Scan(inst, center, radius, prefab, kind)
    local x, y, z = inst.Transform:GetWorldPosition()
    local out = {}
    for _, target in ipairs(TheSim:FindEntities(x, y, z, radius, nil, {'INLIMBO'})) do
        if M.InRange(inst, target, center, radius) then
            local step = M.Classify(target, prefab, kind)
            if step then out[#out+1] = {target=target, step=step} end
        end
    end
    table.sort(out, function(a,b)
        if (a.step == 'pickup') ~= (b.step == 'pickup') then return a.step == 'pickup' end
        return inst:GetDistanceSqToInst(a.target) < inst:GetDistanceSqToInst(b.target)
    end)
    return out
end
return M
