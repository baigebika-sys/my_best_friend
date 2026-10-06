local Screen=require("widgets/screen")
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local ImageButton=require("widgets/imagebutton")
local Text=require("widgets/text")
local TextEdit=require("widgets/textedit")
local Client=require("ybf_chat_client")
local Store=require("ybf_chat_store")
local function button(parent,label,x,y,w,fn)
 local b=parent:AddChild(ImageButton("images/global.xml","square.tex"))
 b:ForceImageSize(w,38);b:SetImageNormalColour(.13,.20,.25,1);b:SetImageFocusColour(.22,.36,.42,1)
 b:SetFont(TALKINGFONT);b:SetTextSize(22);b:SetText(label);b:SetOnClick(fn);b:SetPosition(x,y);return b
end
local Chat=Class(Screen,function(self)
 Screen._ctor(self,"YBFChatScreen");self.store=Client.store;self.page=0;self.version=-1
 self.shade=self:AddChild(Image("images/global.xml","square.tex"));self.shade:SetVAnchor(ANCHOR_MIDDLE);self.shade:SetHAnchor(ANCHOR_MIDDLE);self.shade:SetScaleMode(SCALEMODE_FILLSCREEN);self.shade:SetTint(0,0,0,.45)
 self.root=self:AddChild(Widget("YBFChatRoot"));self.root:SetVAnchor(ANCHOR_MIDDLE);self.root:SetHAnchor(ANCHOR_MIDDLE);self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
 local panel=self.root:AddChild(Image("images/global.xml","square.tex"));panel:SetSize(760,650);panel:SetTint(.055,.075,.09,.98);panel:SetClickable(false)
 self.title=self.root:AddChild(Text(TALKINGFONT,28,"最好的朋友"));self.title:SetPosition(0,290)
 self.targetlabel=self.root:AddChild(Text(TALKINGFONT,18,"聊天对象"));self.targetlabel:SetPosition(-275,245)
 self.targetbutton=button(self.root,"选择朋友 ▾",60,245,430,function()self:ToggleFriends()end)
 self.choices=self.root:AddChild(Widget("FriendChoices"));self.choices:SetPosition(60,220);self.choices:Hide()
 self.rosterelapsed=0;Client.RequestRoster()
 self.rows={}
 for i=1,3 do
  local row=self.root:AddChild(Text(TALKINGFONT,20,""));row:SetRegionSize(680,115);row:EnableWordWrap(true);row:SetHAlign(ANCHOR_LEFT);row:SetPosition(0,165-(i-1)*120);self.rows[i]=row
 end
 self.status=self.root:AddChild(Text(TALKINGFONT,18,""));self.status:SetPosition(0,-180);self.status:SetRegionSize(690,44);self.status:EnableWordWrap(true)
 self.editbg=self.root:AddChild(Image("images/global.xml","square.tex"));self.editbg:SetSize(690,45);self.editbg:SetTint(.13,.17,.20,1);self.editbg:SetPosition(0,-228);self.editbg:SetClickable(false)
 self.input=self.root:AddChild(TextEdit(TALKINGFONT,22,self.store.draft));self.input:SetPosition(0,-228);self.input:SetRegionSize(660,38);self.input:SetHAlign(ANCHOR_LEFT);self.input:SetTextLengthLimit(200);self.input:SetForceEdit(true)
 self.input.OnTextEntered=function()self:Send()end;self.input:SetPassControlToScreen(CONTROL_CANCEL,true)
 self.previous=button(self.root,"更早",-285,-290,100,function()self.page=math.min(self.page+1,math.max(0,math.ceil(#self.store.rows/3)-1));self:Refresh()end)
 self.latest=button(self.root,"更新",-165,-290,100,function()self.page=math.max(0,self.page-1);self:Refresh()end)
 self.retry=button(self.root,"重试",0,-290,100,function()Client.Retry();self.page=0;self:Refresh()end)
 self.send=button(self.root,"发送",155,-290,120,function()self:Send()end)
 self.close=button(self.root,"关闭",295,-290,120,function()self:Close()end)
 do
  self.configbutton=button(self.root,"本机AI配置",250,290,170,function()TheFrontEnd:PushScreen(require('screens/ybf_configscreen')())end)
 end
 self.default_focus=self.input;self:StartUpdating();self:Refresh()
end)
function Chat:OnBecomeActive()
 Chat._base.OnBecomeActive(self);self.input:SetFocus();self.input:SetEditing(true)
end
function Chat:Send()
 local text=self.input:GetString();local name=""
 if not self.store.selected then
  self.store.notice="请先在顶部选择一位朋友。";self:Refresh();return
 end
 if Client.Send(text,name) then self.input:SetString("");self.store.draft="";self.store.target=name;self.page=0 end
 self:Refresh();self.input:SetFocus();self.input:SetEditing(true)
end
function Chat:Refresh()
 self.version=self.store.revision
 local label="选择朋友 ▾"
 for _,f in ipairs(self.store.friends or {}) do if f.guid==self.store.selected then label=f.name.." ▾" end end
 self.targetbutton:SetText(label)
 self.choices:Hide();self.choices.shown=false
 local last=#self.store.rows-self.page*3
 for i,row in ipairs(self.rows) do
  local entry=self.store.rows[last-3+i]
  if entry then
   local prefix=entry.kind=="player" and "我 → "..entry.name or entry.name
   local full=prefix.."："..entry.text
   row:SetString(Store.Preview(full,145));row:SetHoverText(full)
   row:SetColour(entry.kind=="player" and .65 or .92,entry.kind=="error" and .55 or .92,entry.kind=="player" and 1 or .85,1)
  else row:SetString("");row:SetHoverText("") end
 end
 self.status:SetString(self.store:Status())
end
function Chat:ToggleFriends()
 if self.choices.shown then self.choices:Hide();self.choices.shown=false;return end
 self.choices:KillAllChildren()
 local list=self.store.friends or {}
 if #list==0 then self.store.notice="没有可交谈的朋友，请持有对应友谊小花。";self:Refresh();Client.RequestRoster();return end
 self.friendpage=self.friendpage or 0
 local pages=math.ceil(#list/5);self.friendpage=self.friendpage%pages
 for i=self.friendpage*5+1,math.min(#list,self.friendpage*5+5) do
  local f=list[i]
  button(self.choices,f.name.."（"..i.."）",0,-20-(i-self.friendpage*5-1)*40,430,function()
   self.store.selected=f.guid;self.store.revision=self.store.revision+1;self.choices.shown=false;self:Refresh()
  end)
 end
 if pages>1 then button(self.choices,"下一页",0,-220,430,function()self.friendpage=self.friendpage+1;self.choices.shown=false;self:ToggleFriends()end) end
 self.choices:MoveToFront();self.choices:Show();self.choices.shown=true
end
function Chat:OnUpdate(dt)
 self.rosterelapsed=self.rosterelapsed+dt
 if self.rosterelapsed>=2 then self.rosterelapsed=0;Client.RequestRoster() end
 if self.version~=self.store.revision then self:Refresh() end
end
function Chat:Close()
 self.store.draft=self.input:GetString();self.choices:Hide()
 self.input:SetEditing(false);TheFrontEnd:PopScreen(self)
end
function Chat:OnControl(control,down)
 if not down and control==CONTROL_CANCEL then self:Close();return true end
 Chat._base.OnControl(self,control,down);return true
end
function Chat:OnRawKey(key,down)Chat._base.OnRawKey(self,key,down);return true end
return Chat
