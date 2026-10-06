local G = GLOBAL
local ChatServer=G.require("ybf_chat_server")
G.TUNING.YBF_PICKUP_RADIUS=GetModConfigData("pickup_radius") or 32
G.TUNING.YBF_PICKUP_TIMEOUT=GetModConfigData("pickup_timeout") or 60
G.TUNING.YBF_NEEDS={}
for _,key in ipairs({"hunger","health","sanity"}) do
 for _,field in ipairs({"trigger","target"}) do
  local name=key.."_"..field
  G.TUNING.YBF_NEEDS[name]=GetModConfigData(name)
 end
end
G.TUNING.YBF_NEEDS.help_cooldown=GetModConfigData("help_cooldown") or 60
PrefabFiles = { "ybf_friendship_flower" }

G.STRINGS.NAMES.YBF_FRIENDSHIP_FLOWER = "友谊小花"
G.STRINGS.RECIPE_DESC.YBF_FRIENDSHIP_FLOWER = "一颗心，换一位朋友。"
G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.YBF_FRIENDSHIP_FLOWER = "一位朋友的友谊小花。"

-- 原版木牌/牛命名窗口已经调用 SetAutopaused；沿用其单人自动暂停行为。
local writeables = G.require("writeables")
local base = writeables.GetLayout("homesign")
local layout = {}
for k, v in pairs(base) do layout[k] = v end
layout.prompt = "给你的朋友起个名字"
layout.maxcharacters = 20
layout.defaulttext = function() return "威尔逊朋友" end
layout.middlebtn = nil
writeables.AddLayout("ybf_friendship_flower", layout)

AddRecipe2("ybf_friendship_flower", { G.Ingredient("reviver", 1) }, G.TECH.NONE, {
    atlas = "images/inventoryimages.xml",
    image = "petals.tex",
}, { "CHARACTER" })

-- 诀别使用与原版拆包相同的 dolongaction 状态，但不修改全局 UNWRAP。
local farewell = AddAction("YBF_FAREWELL", "诀别", function(act)
    local flower = act.invobject or act.target
    if flower and flower.YBFFarewell then
        flower:YBFFarewell(act.doer)
        return true
    end
    return false
end)
farewell.priority = 5
AddStategraphActionHandler("wilson", G.ActionHandler(farewell, "dolongaction"))
AddStategraphActionHandler("wilson_client", G.ActionHandler(farewell, "dolongaction"))
AddComponentAction("INVENTORY", "inventoryitem", function(inst, doer, actions)
    if inst:HasTag("ybf_friendship_flower") then table.insert(actions, farewell) end
end)
AddComponentAction("SCENE", "inventoryitem", function(inst, doer, actions, right)
    if right and inst:HasTag("ybf_friendship_flower") then table.insert(actions, farewell) end
end)

local pickup=AddAction("YBF_GROUND_PICKUP","拾取",function(act)
    local work=act.doer.components.ybf_work
    return work and work:PerformPickup(act) or false
end)
pickup.priority=1
AddStategraphActionHandler("wilson",G.ActionHandler(pickup,"doshortaction"))

local craft=AddAction("YBF_CRAFT","制作",function(act)
    local work=act.doer.components.ybf_work
    return work and work:PerformCraft(act) or false
end)
AddStategraphActionHandler("wilson",G.ActionHandler(craft,"dolongaction"))

local tech=AddAction("YBF_TECH","靠近科技",function(act)
    local work=act.doer.components.ybf_work
    return work and work:PerformTech(act) or false
end)
tech.distance=2
AddStategraphActionHandler("wilson",G.ActionHandler(tech,"doshortaction"))
local give=AddAction("YBF_GIVE","给予",function(act)
    local work=act.doer.components.ybf_work
    return work and work:PerformGive(act) or false
end)
give.distance=2
AddStategraphActionHandler("wilson",G.ActionHandler(give,"give"))
local equip=AddAction("YBF_EQUIP","装备",function(act)
    local work=act.doer.components.ybf_work
    return work and work:PerformEquip(act) or false
end)
AddStategraphActionHandler("wilson",G.ActionHandler(equip,"doshortaction"))
AddStategraphPostInit("wilson",function(sg)
    G.require("ybf_work_safety").Install(sg,G)
end)

-- 普通玩家也会带一个未激活组件，只有花召唤的威尔逊才激活它。
-- 这样 SpawnSaveRecord 恢复原版 wilson 时能读回伙伴状态。
AddPlayerPostInit(function(inst)
    inst:AddTag("_named")
    if not G.TheWorld.ismastersim then return end
    inst.YBFAnnounce = function(friend, line)
        G.TheNet:Announce(line)
        local c=friend.components.ybf_friend
        local flower=c and c.flower
        local owner=flower and flower:IsValid() and flower.components.inventoryitem:GetGrandOwner()
        if owner and owner.userid then
            friend._ybf_feedback_sequence=(friend._ybf_feedback_sequence or 0)+1
            local text=line:gsub("^%[.-%]%s*", "")
            ChatServer.Emit(G,owner,{kind="feedback",id=tostring(G.TheWorld.GUID).."-"..friend.GUID.."-feedback-"..friend._ybf_feedback_sequence,name=c.name,text=text})
        end
    end
    if not inst.components.named then inst:AddComponent("named") end
    if not inst.components.ybf_friend then inst:AddComponent("ybf_friend") end
end)

-- 原版玩家死亡状态负责音效、动画和掉落。只在动画完成的最后一步，
-- 为模组朋友替换成“留骨架并移除”；真人玩家继续执行原处理。
AddStategraphPostInit("wilson", function(sg)
    local death = sg.states.death
    if not death then return end
    local oldenter = death.onenter
    death.onenter = function(inst, ...)
        if inst:HasTag("ybf_friend") then inst.deathcause = inst.deathcause or "unknown" end
        return oldenter(inst, ...)
    end
    local event = death.events and death.events.animover
    if event then
        local oldfn = event.fn
        event.fn = function(inst, ...)
            if inst:HasTag("ybf_friend") and inst.AnimState:AnimDone()
                and not inst.sg:HasStateTag("dismounting") then
                inst.components.ybf_friend:FinishDeath()
                return
            end
            return oldfn(inst, ...)
        end
    end
end)

-- 原版玩家目标自动产生 GIVETOPLAYER / GIVEALLTOPLAYER；保留其整组选择、
-- 接收检查和控制器“不预先装备”的例外，只移除直接送入口中的 FEEDPLAYER。
AddComponentAction("USEITEM", "inventoryitem", function(item, doer, target, actions)
    if target == nil or not target:HasTag("ybf_friend") then return end
    for i = #actions, 1, -1 do
        if actions[i] == G.ACTIONS.FEEDPLAYER
            or (target:HasTag("ybf_dead") and
                (actions[i] == G.ACTIONS.GIVETOPLAYER or actions[i] == G.ACTIONS.GIVEALLTOPLAYER)) then
            table.remove(actions, i)
        end
    end
end)

-- Both UI and /friend call the same sender; neither simulates public chat.
local YBFCommunication = G.require("ybf_communication")
local function send(player,text,name,tag,guid)
    if not G.TheWorld or not G.TheWorld.ismastersim then return end
    if not G.TheWorld._ybf_chat_sender then
        G.TheWorld._ybf_chat_sender=ChatServer.New(G,G.TheWorld,YBFCommunication)
    end
    G.TheWorld._ybf_chat_sender:Send(player,text,name,tag,guid)
end
AddModRPCHandler("my_best_friend","roster",function(player)
    if not G.TheWorld or not G.TheWorld.ismastersim or not player or not player:IsValid() then return end
    local now=G.GetTime()
    if player._ybf_roster_time and now-player._ybf_roster_time<1 then return end
    player._ybf_roster_time=now
    local list={}
    for _,flower in pairs(G.Ents) do
        if flower:IsValid() and flower:HasTag("ybf_friendship_flower") and flower.components.inventoryitem
            and flower.components.inventoryitem:GetGrandOwner()==player then
            local f=flower._ybf_friend
            if f and f:IsValid() and f.components.ybf_friend and not f.components.health:IsDead() then
                list[#list+1]={guid=f.GUID,name=f.components.ybf_friend.name}
            end
        end
    end
    table.sort(list,function(a,b)return a.guid<b.guid end)
    ChatServer.Emit(G,player,{kind="roster",friends=list})
end)
AddModRPCHandler("my_best_friend","send",send)
AddModRPCHandler("my_best_friend","message",function(player,raw)
    if type(raw)~="string" or #raw>800 then return end
    local text,name=YBFCommunication.Parse(raw)
    if text then send(player,text,name or "","legacy-"..tostring(G.GetTimeReal())) end
end)
AddClientModRPCHandler("my_best_friend","event",function(raw)G.require("ybf_chat_client").Receive(raw)end)
AddClassPostConstruct("screens/chatinputscreen",function(self)
    local oldrun=self.Run
    self.Run=function(screen,...)
        local raw=screen.chat_edit and screen.chat_edit:GetString()
        local text,name=YBFCommunication.Parse(raw)
        if text~=nil then G.require("ybf_chat_client").Send(text,name,true);return end
        return oldrun(screen,...)
    end
end)
if not G.TheNet:IsDedicated() then
    AddClassPostConstruct("screens/redux/multiplayermainscreen",function()G.require("ybf_chat_client").Reset()end)
    AddClassPostConstruct("widgets/controls",function(self)
        if self._ybf_chat_button then return end
        G.require("ybf_chat_client").ClearWaiting()
        local ImageButton=G.require("widgets/imagebutton")
        local b=self:AddChild(ImageButton("images/global.xml","square.tex"))
        b:ForceImageSize(130,40);b:SetFont(G.TALKINGFONT);b:SetTextSize(22);b:SetText("朋友聊天")
        b:SetHAnchor(G.ANCHOR_LEFT);b:SetVAnchor(G.ANCHOR_TOP);b:SetPosition(85,-185)
        b:SetOnClick(function()
            local active=G.TheFrontEnd:GetActiveScreen()
            if active and active.name=="YBFChatScreen" then return end
            G.TheFrontEnd:PushScreen(G.require("screens/ybf_chatscreen")())
        end)
        self._ybf_chat_button=b
    end)
end
