-- Tests real modmain registration/UI routing and bridge with mock game objects.
-- No engine, network replication, or animation is simulated.
package.path = "my_best_friend/scripts/?.lua;" .. package.path
local function noop() end
local rpc_handler, ui_hook, query_callback, client_handler, player_hook
local classhooks={}
local handlers={};local encoded={};local wireseq=0;local events={}
local now, notices, requests, talks = 0, {}, {}, {}
local wire_response
local function entity(guid, tags)
    local e={GUID=guid,components={},valid=true,tags=tags or {},listeners={}}
    function e:IsValid() return self.valid end
    function e:AddTag(tag)self.tags[tag]=true end
    function e:HasTag(tag) return self.tags[tag] or false end
    function e:GetDisplayName() return "玩家" end
    function e:ListenForEvent(event,fn,source)
        source=source or self
        source.listeners[event]=source.listeners[event] or {}
        source.listeners[event][fn]=true
    end
    function e:RemoveEventCallback(event,fn,source)
        source=source or self
        if source.listeners[event] then source.listeners[event][fn]=nil end
    end
    function e:PushEvent(event)
        local copy={}
        for fn in pairs(self.listeners[event] or {}) do copy[#copy+1]=fn end
        for _,fn in ipairs(copy) do fn(self) end
    end
    function e:DoPeriodicTask(_,fn) self.tick=fn;return {Cancel=noop} end
    return e
end
local player=entity(1,{player=true});player.userid="test-player"
local friend=entity(2,{ybf_friend=true})
local flower=entity(3,{ybf_friendship_flower=true})
local world=entity(4);world.ismastersim=true;world.state={cycles=5,phase="day",season="autumn"}
friend.components.health={currenthealth=80,maxhealth=100,IsDead=function() return friend.dead or false end}
friend.components.ybf_friend={active=true,name="小白",flower=flower}
friend.components.talker={Say=function(_,text) talks[#talks+1]=text end}
flower._ybf_friend=friend
flower.components.inventoryitem={GetGrandOwner=function() return flower.owner end}
flower.owner=player
GetModConfigData=function()return nil end
GLOBAL={TUNING={},STRINGS={NAMES={},RECIPE_DESC={},CHARACTERS={GENERIC={DESCRIBE={}}}},
    Ingredient=noop,TECH={NONE={}},ActionHandler=noop,TheWorld=world,
    Ents={player,friend,flower},ThePlayer=player,math=math,
    GetTimeReal=function() return now*1000 end,
    TheNet={IsDedicated=function()return false end,Announce=function(_,line) notices[#notices+1]=line end},
    TheSim={QueryServer=function(_,url,cb,method,body)
        if url=="http://127.0.0.1:8765/tasks" and method=="POST" then
            requests[#requests+1]=body;query_callback=cb
        elseif method=="GET" then assert(url:find("?instance=",1,true));query_callback=cb
        else assert(url:find("/cancel?instance=",1,true));cb("",true,200) end
    end},json={encode_compliant=function(d)wireseq=wireseq+1;local k='json-'..wireseq;encoded[k]=d;return k end,decode=function(d)return encoded[d] or wire_response end},
    SendModRPCToClient=function(_,userid,raw)assert(userid==player.userid);events[#events+1]=encoded[raw];client_handler(raw)end,
    GetClientModRPC=function()return {}end}
GLOBAL.require=function(name)
    if name=="writeables" then return {GetLayout=function() return {} end,AddLayout=noop} end
    return require(name)
end
AddRecipe2=noop
AddAction=function() return {} end
AddStategraphActionHandler=noop
AddComponentAction=noop
AddPlayerPostInit=function(fn)player_hook=fn end
AddStategraphPostInit=noop
AddModRPCHandler=function(ns,name,fn)handlers[name]=fn;if name=="message" then rpc_handler=fn end end
AddClientModRPCHandler=function(ns,name,fn)client_handler=fn end
AddClassPostConstruct=function(path,fn)classhooks[path]=fn;if path=="screens/chatinputscreen" then ui_hook=fn end end
GetModRPC=function(ns,name) return {namespace=ns,name=name} end
SendModRPCToServer=function(id,...)handlers[id.name](player,...) end
ThePlayer=player;json=GLOBAL.json
modimport=function()error('configuration must not be imported during mod startup')end
dofile("my_best_friend/modmain.lua")
local vanilla=0
local text="普通玩家聊天"
local screen={chat_edit={GetString=function() return text end},Run=function() vanilla=vanilla+1 end}
ui_hook(screen)
screen:Run();assert(vanilla==1 and #requests==0)
text="/friendship 你好";screen:Run();assert(vanilla==2)
text="/dance";screen:Run();assert(vanilla==3)
text="/friend 你好";screen:Run();assert(vanilla==3 and #requests==1)
local req=encoded[requests[1]];assert(req.message=="你好" and req.friend_name=="小白")
now=0.1
wire_response={protocol=req.protocol,request_id=req.request_id,friend_id=req.friend_id,task_id=req.request_id,instance_id=string.rep("a",32),state="done",action="none",reply="我收到你的消息了"}
query_callback("body",true,200)
assert(talks[1]=="我收到你的消息了")
assert(notices[2]=="[小白] 我收到你的消息了")
assert(#notices==2)
local Client=require('ybf_chat_client')
assert(#Client.store.rows==2 and Client.store.rows[1].kind=='player' and Client.store.rows[2].kind=='reply')
assert(not Client.store:Status():find('正在'))
assert(notices[1]=='[玩家 → 小白] 你好' and notices[2]=='[小白] 我收到你的消息了')
local before=#Client.store.rows;Client.Receive('json-'..wireseq);assert(#Client.store.rows==before)
local outgoing=#requests;handlers.send(player,'你好','','ui-1');assert(#requests==outgoing)
print("PASS both entry points, public clean messages, client echo, no duplicate replay and completed waiting status")
now=1;text="/friend 长任务";screen:Run();req=encoded[requests[#requests]]
wire_response={protocol=req.protocol,request_id=req.request_id,friend_id=req.friend_id,task_id=req.request_id,instance_id=string.rep("a",32),state="pending"}
query_callback("body",true,202)
now=3;world.tick();wire_response.state="done";wire_response.action="none";wire_response.reply="我收到你的消息了";query_callback("body",true,200)
assert(#talks==2)
print("PASS real adapter submits pending task, polls using GET and displays completion")
now=4;text="/friend 小白|你好";screen:Run();local late=query_callback
flower:PushEvent("onremove");flower.valid=false
assert(world._ybf_communication.count==0)
req=encoded[requests[#requests]]
local n=#notices
wire_response={protocol=req.protocol,request_id=req.request_id,friend_id=req.friend_id,task_id=req.request_id,instance_id=string.rep("a",32),state="done",action="none",reply="我收到你的消息了"}
late("body",true,200)
assert(#notices==n and #talks==2)
print("PASS flower removal cancels request and suppresses late reply")
flower.valid=true;now=5;text="/friend 你好";screen:Run()
friend.dead=true;friend:PushEvent("death")
assert(world._ybf_communication.count==0)
assert(#talks==2)
print("PASS death event cancels request")
friend.dead=false;now=6;flower.owner=entity(5,{player=true})
local previous=#requests;screen:Run();assert(#requests==previous)
print("PASS rejects flowers owned by another player")
world:PushEvent("onremove");assert(world._ybf_communication.closed)
print("PASS world shutdown cleanup")

assert(encoded[requests[1]].game_state.health.current==80)
assert(encoded[requests[1]].game_state.time.day==6)
assert(encoded[requests[1]].game_state.sanity.available==false)
print("PASS snapshot health day missing sanity")
-- Meaningful local feedback goes to its owner's window once, in addition to public chat.
flower.owner=player;friend.components.named={};player_hook(friend)
local rows=#Client.store.rows;local count=#notices
friend:YBFAnnounce('[小白] 捡到了6个树枝，还差4个。')
assert(#notices==count+1 and #Client.store.rows==rows+1 and Client.store.rows[#Client.store.rows].kind=='feedback')
-- Failure remains private; retry reuses the same interface and new request identity.
world.valid=true;world._ybf_communication=nil;flower.owner=player;friend.dead=false;now=20
local startnotices=#notices;assert(Client.Send('你好',''));query_callback('',false,0)
assert(#notices==startnotices+1 and Client.store.rows[#Client.store.rows].kind=='error')
assert(not Client.store:Status():find('正在'))
now=21;assert(Client.Retry());req=encoded[requests[#requests]]
wire_response={protocol=req.protocol,request_id=req.request_id,friend_id=req.friend_id,task_id=req.request_id,instance_id=string.rep('a',32),state='done',action='none',reply='恢复了'}
query_callback('body',true,200);assert(Client.store.rows[#Client.store.rows].text=='恢复了')
print('PASS meaningful feedback in window, connection failure private, retry recovers without duplicate public errors')

-- Vanilla lifecycle: HUD constructor finishes with controls=nil; SetMainCharacter
-- later constructs Controls. Hook the latter instead of indexing a future field.
assert(classhooks['screens/playerhud']==nil)
local earlyhud={controls=nil};assert(earlyhud.controls==nil)
local mockbutton={}
for _,method in ipairs({'ForceImageSize','SetFont','SetTextSize','SetText','SetHAnchor','SetVAnchor','SetPosition'})do mockbutton[method]=function()end end
function mockbutton:SetOnClick(fn)self.click=fn end
local oldrequire=GLOBAL.require
GLOBAL.require=function(name)
 if name=='widgets/imagebutton' then return function()return mockbutton end end
 return oldrequire(name)
end
local controls={count=0}
function controls:AddChild(child)self.count=self.count+1;return child end
classhooks['widgets/controls'](controls);earlyhud.controls=controls
assert(controls.count==1 and controls._ybf_chat_button==mockbutton and mockbutton.click)
classhooks['widgets/controls'](controls);assert(controls.count==1)
local second={count=0,AddChild=controls.AddChild};classhooks['widgets/controls'](second);assert(second.count==1)
GLOBAL.require=oldrequire
print('PASS native delayed HUD controls lifecycle, button constructed after Controls, no duplicate installation')

local other=entity(22,{ybf_friend=true});other.components.health={IsDead=function()return false end};other.components.ybf_friend={name="小白"}
local otherflower=entity(23,{ybf_friendship_flower=true});otherflower._ybf_friend=other;otherflower.components.inventoryitem={GetGrandOwner=function()return player end}
GLOBAL.Ents={friend,flower,other,otherflower};flower.owner=player;flower.valid=true;friend.valid=true;friend.dead=false
GLOBAL.GetTime=function()return now end
local Comm=require('ybf_communication')
assert(not Comm.Context(GLOBAL,player,nil))
assert(Comm.Context(GLOBAL,player,"小白",22).friend==other)
assert(not Comm.Context(GLOBAL,player,nil,999))
handlers.roster(player);assert(events[#events].kind=='roster' and #events[#events].friends==2)
other.valid=false;now=now+2;handlers.roster(player);assert(#events[#events].friends==1)
print('PASS server-owned roster updates, duplicate names resolved by entity ID, stale IDs rejected')
