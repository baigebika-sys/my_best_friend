-- Real communication and communication core dispatch new actions to work.
package.path='my_best_friend/scripts/?.lua;'..package.path
local Communication=require('ybf_communication')
local now=0
local wires={};local wire=0
local function encode(d)wire=wire+1;local k=tostring(wire);wires[k]=d;return k end
local function e(guid)
 local t={GUID=guid,components={}}
 function t:IsValid()return true end
 function t:HasTag()return false end
 function t:GetDisplayName()return '玩家' end
 function t:ListenForEvent()end
 function t:RemoveEventCallback()end
 function t:DoPeriodicTask()return {Cancel=function()end}end
 return t
end
local world=e(1);world.state={}
local owner=e(2);owner.userid='u'
local friend=e(3);local flower=e(4)
local work={calls={},busy=true,Snapshot=function()return {radius=12,nearby={{resource='rocks',action='mine',tool='pickaxe'}}}end}
function work:Request(kind,item,n,player)self.calls[#self.calls+1]={kind,item,n,player};return true end
function work:Start(item,n)self.calls[#self.calls+1]={'pickup',item,n};return true end
function work:IsBusy()return self.busy end
function work:Cancel(restore)self.restore=restore;self.busy=false end
friend.components.ybf_work=work
friend.components.ybf_friend={active=true,flower=flower,mode='wait',SetMode=function(c,m)c.mode=m;return true end}
friend.components.health={IsDead=function()return false end}
flower._ybf_friend=friend;flower.components.inventoryitem={GetGrandOwner=function()return owner end}
local callback,request,replies
local G={GetTimeReal=function()return now*1000 end,math=math,json={encode_compliant=encode,decode=function(s)return wires[s]end},
 TheSim={QueryServer=function(_,url,cb,method,body)if method=='POST' and url:match('/tasks$')then callback=cb;request=wires[body]else cb('',true,200)end end},
 TheNet={Announce=function()end},SendModRPCToClient=function(_,_,raw)local v=wires[raw];if v.kind=='reply' or v.kind=='error'then replies=v.text end end,GetClientModRPC=function()return {}end}
local core=Communication.New(G,world)
local ctx={friend=friend,flower=flower,player=owner,playerkey='u',playername='玩家',name='朋友',clienttag='test'}
for _,kind in ipairs({'collect','craft','give'})do
 now=now+1;assert(core:Send(ctx,'测试当前指令'))
 assert(request.game_state.work.radius==12 and request.game_state.work.nearby[1].action=='mine')
 local result={protocol=request.protocol,request_id=request.request_id,friend_id=request.friend_id,task_id=request.request_id,
 instance_id=string.rep('a',32),state='done',reply='尚未完成',action=kind,item=kind=='craft' and 'pickaxe' or 'rocks',quantity=3}
 callback(encode(result),true,200)
 local call=work.calls[#work.calls];assert(call[1]==kind and call[3]==3 and call[4]==owner and replies)
end
now=now+1;assert(core:Send(ctx,'停止任务'))
callback(encode({protocol=request.protocol,request_id=request.request_id,friend_id=request.friend_id,task_id=request.request_id,
 instance_id=string.rep('a',32),state='done',reply='停止',action='stop'}),true,200)
assert(work.restore==true and not work.busy)
print('PASS new action allowlist, actual bridge snapshot/dispatch, player-bound give, stop restores original mode')
-- Equipped and held inventory entries are part of the authoritative snapshot.
local hand=e(90);hand.prefab='pickaxe';hand.components.inventoryitem={};function hand:GetDisplayName()return '鹤嘴锄'end
local food=e(91);food.prefab='bonestew';food.components.inventoryitem={};function food:GetDisplayName()return '炖肉汤'end
friend.components.inventory={itemslots={food},equipslots={hands=hand},GetOverflowContainer=function()end,GetEquippedItem=function(_,slot)return slot=='hands' and hand or nil end}
function work:RequestPlan(entries,player)self.plan=entries;self.owner=player;return true end
now=now+1;assert(core:Send(ctx,'你持有什么'))
local items=request.game_state.inventory.items
local found=false;local alias=false
for _,i in ipairs(items)do if i.prefab=='pickaxe'then found=i.equipped and i.location=='装备中' end;if i.prefab=='bonestew'then alias=i.aliases[1]=='炖肉汤' end end
assert(found and alias)
callback(encode({protocol=request.protocol,request_id=request.request_id,friend_id=request.friend_id,task_id=request.request_id,
 instance_id=string.rep('a',32),state='done',reply='我不知道',action='none',item=nil,quantity=nil}),true,200)
assert(replies:find('鹤嘴锄'))
now=now+1;assert(core:Send(ctx,'采完给我'))
local plan={{kind='collect',item='rocks',quantity=3},{kind='give',item='rocks',quantity=3}}
callback(encode({protocol=request.protocol,request_id=request.request_id,friend_id=request.friend_id,task_id=request.request_id,
 instance_id=string.rep('a',32),state='done',reply='我会尝试',action='plan',item=plan,quantity=nil}),true,200)
assert(work.plan==plan and work.owner==owner)
local oldsnapshot=work.Snapshot;work.Snapshot=function()error('mock snapshot failure')end
now=now+1;local ok,why=core:Send(ctx,'你好');assert(not ok and why=='请求编码失败')
work.Snapshot=oldsnapshot
print('PASS equipped tool and food alias snapshot, authoritative held-item answer, plan dispatch and failed snapshot returns a visible reason')

local callcount=#work.calls
now=now+1;assert(core:Send(ctx,'我想要一个石砖'))
callback(encode({protocol=request.protocol,request_id=request.request_id,friend_id=request.friend_id,task_id=request.request_id,
 instance_id=string.rep('a',32),state='error',diagnostic={category='decision_schema',code='invalid_quantity',reason='数量必须是整数'}}),true,200)
assert(#work.calls==callcount and replies:find('指令解析失败') and replies:find('invalid_quantity'))
print('PASS invalid provider decision creates classified chat UI error and zero work dispatch')
-- Normal conversation must leave active work/mode unchanged and display dialogue.
local beforecalls=#work.calls;local beforemode=friend.components.ybf_friend.mode
now=now+1;assert(core:Send(ctx,'你好，今天过得怎么样？'))
callback(encode({protocol=request.protocol,request_id=request.request_id,friend_id=request.friend_id,task_id=request.request_id,
 instance_id=string.rep('a',32),state='done',reply='你好呀，见到你很开心。',action='none'}),true,200)
assert(replies=='你好呀，见到你很开心。' and #work.calls==beforecalls and friend.components.ybf_friend.mode==beforemode)
assert(not replies:find('ms') and not replies:find('task completed'))
print('PASS ordinary conversation reply through communication preserves work/mode and contains no transport status')
