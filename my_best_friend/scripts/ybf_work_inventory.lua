-- Owned inventory only: never inspect open chests or other players' containers.
local M = {}
function M.Size(item)
    return item.components.stackable and item.components.stackable:StackSize() or 1
end
function M.Items(inst, equipment)
    local inv = inst.components.inventory
    local out, seen = {}, {}
    local function add(item)
        if item and item:IsValid() and not seen[item] then
            seen[item] = true
            out[#out + 1] = item
        end
    end
    for _, item in pairs(inv.itemslots or {}) do add(item) end
    add(inv.activeitem)
    local overflow = inv:GetOverflowContainer()
    for _, item in pairs(overflow and overflow.slots or {}) do add(item) end
    if equipment then
        for _, item in pairs(inv.equipslots or {}) do add(item) end
    end
    return out
end
function M.Count(inst, prefab, equipment)
    local count = 0
    for _, item in ipairs(M.Items(inst, equipment)) do
        if item.prefab == prefab then count = count + M.Size(item) end
    end
    return count
end
function M.Find(inst, prefab)
    for _, item in ipairs(M.Items(inst, false)) do
        if item.prefab == prefab then return item end
    end
end
function M.Label(prefab)
    local names = STRINGS and STRINGS.NAMES
    return names and names[string.upper(prefab)] or prefab
end
-- Conservative preflight without spawning a sample product. Vanilla supported
-- recipes have fixed stack limits; free slots also allow an equipment swap.
function M.Room(inst, prefab, count)
    local inv = inst.components.inventory
    local room = 0
    local function slots(items, maximum, stacks)
        for slot = 1, maximum or 0 do
            local item = items[slot]
            if not item then
                room = room + 1 -- conservative: no assumed product stack limit
            elseif item.prefab == prefab and item.components.stackable then
                room = room + item.components.stackable:RoomLeft()
            end
        end
    end
    slots(inv.itemslots, inv.maxslots, inv.acceptsstacks ~= false)
    local overflow = inv:GetOverflowContainer()
    if overflow then slots(overflow.slots, overflow.numslots, overflow.acceptsstacks ~= false) end
    return room >= count
end
return M
