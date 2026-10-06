-- 独立的阈值逻辑，既能在游戏使用，也能脱离游戏测试。
local M = {}
M.rules = {
    hunger = { normal = 100, urgent = 20, normal_text = "我有点饿了", urgent_text = "我快饿死了！" },
    sanity = { normal = 100, urgent = 30, normal_text = "我的头有点晕", urgent_text = "我要崩溃了！" },
    health = { normal = 100, urgent = 20, normal_text = "我有点受伤了", urgent_text = "我要死了！" },
}
function M.Initial(key, value)
    local r = M.rules[key]
    return { normal = value <= r.normal, urgent = value <= r.urgent }
end
function M.Step(key, flags, value)
    local r = M.rules[key]
    local normal = value <= r.normal
    local urgent = value <= r.urgent
    local text
    if urgent and not flags.urgent then
        text = r.urgent_text
    elseif normal and not flags.normal and not urgent then
        text = r.normal_text
    end
    -- 回升到阈值以上即重新允许下一次下降提示；跳过两级时同时标记两级。
    flags.normal = normal
    flags.urgent = urgent
    return text
end
return M
