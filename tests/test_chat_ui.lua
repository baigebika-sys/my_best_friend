package.path='my_best_friend/scripts/?.lua;'..package.path
local Store=require('ybf_chat_store')
local s=Store.New();local tag=s:Outgoing('', '你好');assert(#s.rows==1 and s:Status():find('正在'))
s:Event({kind='sent',tag=tag,name='小白'});assert(#s.rows==1 and s.rows[1].name=='小白')
s:Event({kind='accepted',tag=tag});assert(#s.rows==1)
s:Event({kind='reply',id='one',name='小白',text='你好',tag=tag});assert(#s.rows==2 and s:Status()=='')
s:Event({kind='reply',id='one',name='小白',text='你好',tag=tag});assert(#s.rows==2)
for i=1,1000 do s:Add('id-'..i,'feedback','朋友',string.rep('长',100))end
assert(#s.rows<=200 and s.bytes<=40000 and #s.seenorder<=512)
assert(Store.Preview('朋友你好',2)=='朋友…')
print('PASS immediate echo, reply dedup, UI-only waiting, UTF-8 preview and bounded session history')
-- Lightweight widget lifecycle mock; visual layout, IME and engine focus need DST.
local Node={};Node.__index=Node
function Node._ctor(self,name)self.name=name;self.children={}end
function Node:AddChild(child)self.children[#self.children+1]=child;return child end
function Node:SetString(s)self.string=s end
function Node:GetString()if self.password then return string.rep('*',#(self.string or '')) end;return self.string or '' end
function Node:GetLineEditString()return self.string or '' end
function Node:SetFocus()self.focus=true end
function Node:SetEditing(v)self.editing=v end
function Node:SetOnClick(fn)self.click=fn end
function Node:OnControl()return false end
function Node:OnRawKey()return false end
function Node:OnBecomeActive()end
for _,name in ipairs({'Hide','Show','KillAllChildren','MoveToFront','SetHAnchor','SetVAnchor','SetScaleMode','SetTint','SetSize','SetClickable','SetPosition','SetRegionSize','EnableWordWrap','SetHAlign','SetTextLengthLimit','SetForceEdit','SetPassControlToScreen','StartUpdating','ForceImageSize','SetImageNormalColour','SetImageFocusColour','SetFont','SetTextSize','SetText','SetHoverText','SetColour'})do Node[name]=function()end end
function Class(base,ctor)
 local c={_base=base};c.__index=c
 setmetatable(c,{__index=base,__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end});return c
end
local function constructor(name,string)local o=setmetatable({},Node);Node._ctor(o,name);o.string=string;return o end
setmetatable(Node,{__call=function(_,name)return constructor(name)end})
for _,path in ipairs({'widgets/screen','widgets/widget'})do package.preload[path]=function()return Node end end
for _,path in ipairs({'widgets/image','widgets/imagebutton','widgets/text','widgets/textedit'})do package.preload[path]=function()return function(a,b,text)return constructor(path,text)end end end
TALKINGFONT='font';ANCHOR_MIDDLE=0;ANCHOR_LEFT=1;SCALEMODE_FILLSCREEN=1;SCALEMODE_PROPORTIONAL=2;CONTROL_CANCEL=1
local Client=require('ybf_chat_client');Client.store=Store.New();local sends=0
ThePlayer={};GetModRPC=function()return {}end;SendModRPCToServer=function()sends=sends+1 end
Client.store.friends={{guid=1,name="小白"},{guid=2,name="小白"}};Client.store.selected=2
local active=nil;TheFrontEnd={GetActiveScreen=function()return active end,PushScreen=function(_,screen)active=screen;screen:OnBecomeActive()end,PopScreen=function(_,screen)assert(active==screen);active=nil end}
local Chat=require('screens/ybf_chatscreen');TheNet={GetIsServer=function()return false end}
local screen=Chat();assert(screen.configbutton, "host client must retain config entry when GetIsServer is false");TheFrontEnd:PushScreen(screen)
assert(active==screen and screen.input.editing)
screen.input:SetString('你好');screen:Send();assert(sends==2 and #Client.store.rows==1)
assert(screen:OnControl(999,true) and screen:OnRawKey(999,true))
screen:Close();assert(active==nil and not screen.input.editing)
Client.store:Event({kind='reply',id='late-closed',tag='ui-1',name='小白',text='窗口关闭后收到'})
local reopened=Chat();TheFrontEnd:PushScreen(reopened);assert(reopened.store.rows[2].text=='窗口关闭后收到')
assert(reopened:OnControl(CONTROL_CANCEL,false) and active==nil)
print('PASS native-screen lifecycle mock: send once, closed-window reception, reopen history, close releases modal focus')

local pick=Chat();pick:ToggleFriends();assert(pick.choices.shown)
Client.store.selected=1;pick.input:SetString('给第一位');pick:Send()
assert(Client.store.last_sent.guid==1)
Client.store.selected=2;Client.Retry();assert(Client.store.last_sent.guid==1)
print('PASS two same-name friends: identity selection and retry retains original recipient')

Client.store.friends={{guid=2,name="小白"}};local before=sends;assert(not Client.Retry());assert(sends==before)
print('PASS retry does not redirect to remaining friend after recipient removal')
-- Configuration UI uses direct local HTTP, never game RPC or world options.
Node.SetPassword=function(self,v)self.password=v end
local wire={};local seq=0;json={encode_compliant=function(d)seq=seq+1;wire[tostring(seq)]=d;return tostring(seq)end,decode=function(raw)return assert(wire[raw])end}
local pending;TheSim={QueryServer=function(_,url,cb,method,raw)pending={url=url,cb=cb,method=method,body=raw and wire[raw]}end}
local function respond(d,code)local key=json.encode_compliant(d);pending.cb(key,true,code or 200)end
local Config=require('screens/ybf_configscreen');local cfg=Config();TheFrontEnd:PushScreen(cfg)
assert(cfg.key.password and pending.url:find('/config/status',1,true));respond({token='local-token',configured=false,ai_mode=true})
local rpcbefore=sends;cfg.key:SetString('sk-private-mock');assert(cfg.key:GetString()=='***************');assert(cfg.key:GetLineEditString()=='sk-private-mock');cfg:Save();assert(cfg.key:GetString()=='')
assert(pending.method=='POST' and pending.body.key=='sk-private-mock' and sends==rpcbefore)
respond({saved=true});assert(not cfg.busy)
cfg:Test();respond({test_id='test-id',state='pending'});cfg:OnUpdate(2)
assert(pending.url:find('/config/test/test-id',1,true));respond({state='done',elapsed_ms=200,prompt_tokens=8,completion_tokens=2,total_tokens=10})
assert(cfg.status:GetString():find('连接成功'));assert(not cfg.busy)
cfg:Connect();local late=pending.cb;cfg:OnUpdate(9);assert(not cfg.busy)
late(json.encode_compliant({token='late-token'}),true,200);assert(not cfg.token)
cfg:Close();assert(active==nil and cfg.key:GetString()=='' and sends==rpcbefore)
print('PASS config password mask, direct-local save, cleared key, asynchronous test usage, timeout and stale callback guard')

assert(not io.open('my_best_friend/modworldgenmain.lua','r'))
assert(not io.open('my_best_friend/modservercreationmain.lua','r'))
local main=assert(io.open('my_best_friend/modmain.lua','r'));local source=main:read('*a');main:close()
assert(not source:find('modservercreationmain',1,true))
print('PASS no world-creation configuration entry or eager custom config-screen load; client-mode chat entry retained')

print('PASS password display returns stars but saved HTTP payload retains real letters and numbers')
