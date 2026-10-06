local Core = require("ybf_comm_core")
local Inventory = require("ybf_work_inventory")
local ChatServer = require("ybf_chat_server")
local M = {}
local function Trim(s) return s:match("^%s*(.-)%s*$") end

function M.Parse(text)
    if type(text) ~= "string" then return nil end
    text = Trim(text)
    if text ~= "/friend" and not text:match("^/friend%s") then return nil end
    local content = Trim(text:sub(8))
    local name, message = content:match("^(.-)|(.*)$")
    if name then return Trim(message), Trim(name) end
    return content, nil
end

function M.Context(G, player, name, guid)
    local matches = {}
    for _, flower in pairs(G.Ents) do
        if flower:IsValid() and flower:HasTag("ybf_friendship_flower")
            and flower.components.inventoryitem
            and flower.components.inventoryitem:GetGrandOwner() == player then
            local friend = flower._ybf_friend
            if friend and friend:IsValid() and friend.components.ybf_friend
                and not friend.components.health:IsDead()
                and (not name or friend.components.ybf_friend.name == name)
                and (not guid or friend.GUID == guid) then
                matches[#matches + 1] = { friend = friend, flower = flower, player = player,
                    playerkey = player.userid or tostring(player.GUID),
                    playername = player:GetDisplayName(), name = friend.components.ybf_friend.name }
            end
        end
    end
    if #matches == 0 then return nil, "请持有一朵对应活着朋友的友谊小花（可放背包）；名字须完全一致" end
    if #matches > 1 then return nil, "有多位同名或未指定的朋友；请用 /friend 朋友名字|你好，并给朋友不同名字" end
    return matches[1]
end

function M.New(G, world)
    local function valid(r)
        local f, flower, p = r.friend, r.flower, r.player
        return world:IsValid() and f:IsValid() and flower:IsValid() and p:IsValid()
            and not p:HasTag("playerghost") and not f:HasTag("ybf_dead")
            and f.components.health and not f.components.health:IsDead()
            and f.components.ybf_friend and f.components.ybf_friend.active
            and not f.components.ybf_friend.dead
            and f.components.ybf_friend.flower == flower and flower._ybf_friend == f
            and flower.components.inventoryitem:GetGrandOwner() == p
    end
    local function clean(s) return tostring(s):gsub("[%c]", " ") end
    local core = Core.New({
        session = tostring(world.GUID) .. "-" .. tostring(G.GetTimeReal()) .. "-"
            .. tostring(G.math.random(100000, 999999)) .. "-" .. tostring(G.math.random(100000, 999999)),
        apply = function(r,action,reply,d)
            if action=="none" then
                if r.text:find("持有什么",1,true) or r.text:find("手上有什么",1,true) or r.text:find("手里有什么",1,true) then
                    local inv=r.friend.components.inventory
                    local hand=inv and inv:GetEquippedItem(G.EQUIPSLOTS and G.EQUIPSLOTS.HANDS or "hands")
                    return hand and ("我手上拿着"..hand:GetDisplayName().."（"..hand.prefab.."）。") or "我现在空着手。"
                end
                return reply
            end
            local work=r.friend.components.ybf_work
            local needs=r.friend.components.ybf_needs
            if action=="eat" then
                if not needs then error("补给组件未就绪") end
                local ok,err=needs:RequestEat(d.item,d.quantity)
                if not ok then error(err) end
                return "好，我会吃"..d.quantity.."份，吃完再告诉你。"
            end
            if needs then needs:CancelExplicit() end
            if action=="goal" then
                if not work or type(d.item)~='table' then return '[游戏执行受阻] 工作组件或目标数据未就绪。' end
                local ok,why=work:RequestGoal(d.item.targets,d.item.deliver,r.player)
                if not ok then return '[游戏执行受阻] '..tostring(why) end
                local parts={};for _,target in ipairs(d.item.targets) do parts[#parts+1]=target.quantity..'个'..Inventory.Label(target.item) end
                return '好，我帮你准备'..table.concat(parts,'、')..(d.item.deliver and '，准备好了就给你。' or '，先放在我这里。')
            elseif action=="resume" then
                local ok,why=false,'工作组件未就绪'
                if work then ok,why=work:ResumeGoal() end
                return ok and '好，我保留已有进度，重新检查缺口后继续。' or '[游戏执行受阻] '..tostring(why or '没有可恢复的任务')
            elseif action=="equip" then
                local ok,why=work:RequestPlan({{kind='equip',item=d.item,quantity=d.quantity}},r.player)
                return ok and '好，我检查并装备已有物品。' or '[游戏执行受阻] '..tostring(why)
            elseif action=="plan" then
                local ok,why=work:RequestPlan(d.item,r.player)
                if not ok then return why end
                local parts={}
                local verbs={collect="收集",craft="制作",give="交付",tree="砍倒",equip="装备"}
                for _,e in ipairs(d.item) do
                    parts[#parts+1]=(e.ensure and "备齐" or verbs[e.kind] or "处理")..e.quantity..(e.kind=="tree" and "棵树" or "个"..Inventory.Label(e.item))
                end
                return "好，我按顺序"..table.concat(parts,"，").."；实际结果稍后汇报。"
            elseif action=="pickup" then
                if not work or not work:Start(d.item,d.quantity) then error("拾取参数无效") end
                return "好，我检查已有库存，再捡附近缺少的部分；整叠可能多拿一点。"
            elseif action=="collect" or action=="craft" or action=="give" then
                if not work then return "工作组件未就绪。" end
                local ok,why=work:Request(action,d.item,d.quantity,r.player)
                if not ok then return why or "工作参数无效。" end
                return action=="collect" and "好，我检查已有库存、附近目标和工具，按实际入包数量收集。"
                    or action=="craft" and "好，我按实际配方检查材料和科技，制作结果稍后告诉你。"
                    or "好，我只交付指定数量；不能接收时会保留剩余物品。"
            elseif action=="stop" then
                if work and ((work.HasTask and work:HasTask()) or work:IsBusy()) then work:Cancel(true);return "好，我停下任务，回到原来的安排。" end
                return "目前没有正在执行的工作任务。"
            end
            if work then work:Cancel(false) end
            local ok,err=r.friend.components.ybf_friend:SetMode(action)
            if not ok then error(err or "mode change failed") end
            -- Only authoritative engine execution confirms an action.
            return action=="wait" and "好，我在这里等你。" or "好，我继续跟着你。"
        end,
        snapshot = function(ctx)
            local f = ctx.friend
            local function stat(key)
                local c=f.components[key]
                if not c then return {available=false} end
                local value=c.currenthealth or c.current or c.currentsanity
                local maximum=c.maxhealth or c.max or c.maxsanity
                return {available=value~=nil, current=value, maximum=maximum}
            end
            local items={}
            local inv=f.components.inventory
            if inv then
                for _,item in ipairs(Inventory.Items(f,true)) do
                    if #items<60 then
                        local equipped=false
                        for _,v in pairs(inv.equipslots or {}) do if v==item then equipped=true end end
                        items[#items+1]={name=item:GetDisplayName(),prefab=item.prefab,
                            aliases=item.prefab=="bonestew" and {"炖肉汤","肉汤"} or nil,
                            equipped=equipped,location=equipped and "装备中" or item==inv.activeitem and "鼠标持有" or "库存",
                            count=Inventory.Size(item)}
                    end
                end
            end
            return {behavior_mode=f.components.ybf_friend.mode or "follow",health=stat("health"),hunger=stat("hunger"),sanity=stat("sanity"),
                inventory={available=inv~=nil,items=items},
                work=f.components.ybf_work and f.components.ybf_work:Snapshot() or nil,
                supplies=f.components.ybf_needs and f.components.ybf_needs:Snapshot() or nil,
                time={day=(world.state.cycles or 0)+1,phase=world.state.phase,season=world.state.season},
                location=world:HasTag("cave") and "洞穴" or "地面"}
        end,
        timeout = 45,
        http_timeout = 8,
        poll_interval = 2,
        now = function() return G.GetTimeReal() / 1000 end,
        valid = valid,
        encode = G.json.encode_compliant,
        decode = G.json.decode,
        query = function(body, callback)
            G.TheSim:QueryServer("http://127.0.0.1:8765/tasks", callback, "POST", body)
        end,
        poll = function(taskid, instance, callback)
            G.TheSim:QueryServer("http://127.0.0.1:8765/tasks/" .. taskid .. "?instance=" .. instance, callback, "GET")
        end,
        cancel = function(taskid, instance)
            G.TheSim:QueryServer("http://127.0.0.1:8765/tasks/" .. taskid .. "/cancel?instance=" .. instance,
                function(_, success, code)
                    print("[YBF COMM] cancel_best_effort task=" .. taskid .. " success=" .. tostring(success) .. " http=" .. tostring(code))
                end, "POST", "{}")
        end,
        log = function(id, status, ms, detail)
            print(string.format("[YBF COMM] id=%s status=%s rtt_ms=%.0f detail=%s", id, status, ms, clean(detail)))
        end,
        notify = function(r, status, ms, detail, reply)
            local currentname=clean(r.name)
            if status=="sent" then
                G.TheNet:Announce("["..clean(r.playername).." → "..currentname.."] "..clean(r.text))
                ChatServer.Emit(G,r.player,{kind="sent",tag=r.clienttag,id=r.id,name=currentname})
            elseif status=="reply" then
                if r.friend.components.talker then r.friend.components.talker:Say(clean(reply)) end
                G.TheNet:Announce("["..currentname.."] "..clean(reply))
                ChatServer.Emit(G,r.player,{kind="reply",tag=r.clienttag,id=r.id,name=currentname,text=clean(reply)})
            elseif status=="accepted" then
                ChatServer.Emit(G,r.player,{kind="accepted",tag=r.clienttag,id=r.id})
            elseif status=="cancelled" then
                ChatServer.Emit(G,r.player,{kind="cancelled",tag=r.clienttag,id=r.id})
            else
                ChatServer.Emit(G,r.player,{kind="error",tag=r.clienttag,id=r.id.."-error",text=ChatServer.ErrorText(status,detail)})
            end
        end,
        watch = function(r, cancel)
            r.listeners = {}
            for _, v in ipairs({ {r.friend, "death"}, {r.friend, "onremove"},
                {r.flower, "onremove"}, {r.player, "onremove"} }) do
                local fn = function() cancel("朋友死亡、被移除或持有人已离开；请求已取消") end
                world:ListenForEvent(v[2], fn, v[1])
                r.listeners[#r.listeners + 1] = { source = v[1], event = v[2], fn = fn }
            end
        end,
        unwatch = function(r)
            for _, v in ipairs(r.listeners or {}) do world:RemoveEventCallback(v.event, v.fn, v.source) end
            r.listeners = nil
        end,
    })
    local task = world:DoPeriodicTask(0.25, function() core:Tick() end)
    world:ListenForEvent("onremove", function() task:Cancel(); core:Close() end)
    return core
end
return M
