-- Real builder/recipes; dependency inspection is separate from verified BUILD.
local Inventory = require('ybf_work_inventory')
local M = {}
M.allowed = {axe=true, pickaxe=true, cutstone=true, boards=true, rope=true, torch=true}
-- Recipe-only inspection for dependency planning. No consumption or spawning.
function M.PlanRecipe(inst,name)
    local builder=inst.components.builder
    local recipe=GetValidRecipe and GetValidRecipe(name) or AllRecipes[name]
    if not M.allowed[name] or not recipe or recipe.placer or recipe.dropitem or recipe.manufactured then
        return nil,'当前基础范围不能获取或制作'..Inventory.Label(name),'unobtainable_material'
    end
    if not builder or builder.freebuildmode or builder:IsBuildBuffered(name) then
        return nil,'制作器不可用或处于免费/预付材料模式','builder_condition'
    end
    if not builder:CanLearn(name) and not builder:KnowsRecipe(recipe) then
        return nil,'角色条件不允许解锁'..Inventory.Label(name),'recipe_condition'
    end
    local output=recipe.override_numtogive_fn and recipe.override_numtogive_fn(recipe,inst) or recipe.numtogive or 1
    if type(output)~='number' or output<1 or output%1~=0 then return nil,'实际配方产出数量无效','recipe_data' end
    local ingredients={}
    for _,ingredient in ipairs(recipe.ingredients) do
        local amount=math.max(1,RoundBiasedUp(ingredient.amount*builder.ingredientmod))
        ingredients[#ingredients+1]={item=ingredient.type,amount=amount}
    end
    return {recipe=recipe,output=output,ingredients=ingredients}
end
function M.Check(inst, name)
    local builder = inst.components.builder
    local recipe = GetValidRecipe and GetValidRecipe(name) or AllRecipes[name]
    if not M.allowed[name] or not recipe or recipe.placer or recipe.dropitem or recipe.manufactured then
        return nil, '本阶段不支持这个配方'
    end
    if not builder or builder.freebuildmode or builder:IsBuildBuffered(name) then
        return nil, '制作组件不可用或处于免费／预付材料模式，未制作'
    end
    builder:EvaluateTechTrees() -- friend position, not the owner's technology
    local knows = builder:KnowsRecipe(recipe)
    local canlearn = builder:CanLearn(name)
    local canproto = canlearn and CanPrototypeRecipe(recipe.level, builder.accessible_tech_trees)
    if not knows and not canproto then return nil, '尚未解锁配方且当前位置科技条件不足' end
    local heavy = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    if (name == 'axe' or name == 'pickaxe' or name == 'torch') and heavy and heavy:HasTag('heavy') then
        return nil, '正在搬运重物，未制作可能自动装备的工具，避免丢弃物品'
    end
    local missing = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        local amount = math.max(1, RoundBiasedUp(ingredient.amount * builder.ingredientmod))
        local have = Inventory.Count(inst, ingredient.type)
        if have < amount then missing[#missing+1] = Inventory.Label(ingredient.type)..'×'..(amount-have) end
    end
    if #missing > 0 then return nil, '缺少材料：'..table.concat(missing, '、')..'' end
    if not builder:HasIngredients(recipe) then return nil, '配方的材料或角色条件未满足' end
    local output = recipe.override_numtogive_fn and recipe.override_numtogive_fn(recipe, inst) or recipe.numtogive or 1
    if type(output) ~= 'number' or output < 1 or output % 1 ~= 0 then return nil, '配方产出数量无效' end
    if not Inventory.Room(inst, recipe.product, output) then return nil, '背包空间不足，未消耗制作材料' end
    if recipe.canbuild then
        local ok, reason = recipe.canbuild(recipe, inst, inst:GetPosition(), 0, builder.current_prototyper, nil)
        if not ok then return nil, '配方条件不满足：'..tostring(reason or '不可制作') end
    end
    -- Check the actual material selection; never consume from an open chest.
    local owned = {}
    for _, item in ipairs(Inventory.Items(inst, false)) do owned[item] = true end
    local materials = builder:GetIngredients(name)
    local costs = {}
    for prefab, entries in pairs(materials or {}) do
        for item, amount in pairs(entries) do
            if not owned[item] then return nil, '配方选中了非朋友持有的材料，未制作' end
            costs[prefab] = (costs[prefab] or 0) + amount
        end
    end
    return {recipe=recipe, output=output, costs=costs, knows_no_temp=builder:KnowsRecipe(recipe, true),
        canproto_no_temp=CanPrototypeRecipe(recipe.level, builder.accessible_tech_trees_no_temp), canlearn=canlearn}
end
function M.Perform(inst, name, info, act)
    local builder = inst.components.builder
    local before = Inventory.Count(inst, info.recipe.product, true)
    local inputs = {}
    for prefab in pairs(info.costs) do inputs[prefab] = Inventory.Count(inst, prefab) end
    -- Standard BUILD consumes ingredients, creates output and runs vanilla events.
    local ok, reason = ACTIONS.BUILD.fn(act)
    local gained = Inventory.Count(inst, info.recipe.product, true) - before
    local consumed, verified = {}, ok and gained == info.output
    for prefab, expected in pairs(info.costs) do
        consumed[prefab] = inputs[prefab] - Inventory.Count(inst, prefab)
        if consumed[prefab] ~= expected then verified = false end
    end
    if ok then
        -- Same unlock/temp bonus rules as vanilla MakeRecipeFromMenu, without its
        -- fallback that can recursively craft ingredients when materials are absent.
        local usingtemp = not info.knows_no_temp and not info.canproto_no_temp
        if usingtemp then builder:ConsumeTempTechBonuses() end
        if not info.knows_no_temp and info.canproto_no_temp and info.canlearn then
            builder:ActivateCurrentResearchMachine(info.recipe)
            builder:UnlockRecipe(name)
        elseif not info.recipe.nounlock then
            builder:AddRecipe(name)
        else builder:ActivateCurrentResearchMachine(info.recipe) end
    end
    return verified, math.max(0, gained), consumed, reason
end
return M
