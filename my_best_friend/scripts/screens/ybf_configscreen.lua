local Screen=require('widgets/screen')
local Widget=require('widgets/widget')
local Image=require('widgets/image')
local Text=require('widgets/text')
local TextEdit=require('widgets/textedit')
local Button=require('widgets/imagebutton')
local function button(root,label,x,fn)
 local b=root:AddChild(Button('images/global.xml','square.tex'));b:ForceImageSize(150,42);b:SetPosition(x,-150);b:SetFont(TALKINGFONT);b:SetTextSize(22);b:SetText(label);b:SetOnClick(fn);return b
end
local Config=Class(Screen,function(self)
 Screen._ctor(self,'YBFConfigScreen');self.closed=false;self.busy=false;self.elapsed=0;self.timer=0;self.clock=0;self.requestseq=0
 self.root=self:AddChild(Widget('YBFConfigRoot'));self.root:SetHAnchor(ANCHOR_MIDDLE);self.root:SetVAnchor(ANCHOR_MIDDLE);self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
 local bg=self.root:AddChild(Image('images/global.xml','square.tex'));bg:SetSize(760,440);bg:SetTint(.055,.075,.09,1);bg:SetClickable(false)
 local title=self.root:AddChild(Text(TALKINGFONT,28,'DeepSeek 本机配置'));title:SetPosition(0,175)
 local info=self.root:AddChild(Text(TALKINGFONT,20,'仅房主／后台所在电脑需要配置。密钥不发给其他玩家。\n请先运行新版 start_ai.cmd；保存后无需重启后台。'));info:SetRegionSize(700,75);info:EnableWordWrap(true);info:SetPosition(0,105)
 local editbg=self.root:AddChild(Image('images/global.xml','square.tex'));editbg:SetSize(660,45);editbg:SetPosition(0,25);editbg:SetTint(.15,.20,.25,1);editbg:SetClickable(false)
 self.key=self.root:AddChild(TextEdit(TALKINGFONT,22,''));self.key:SetRegionSize(630,38);self.key:SetPosition(0,25);self.key:SetTextLengthLimit(256);self.key:SetPassword(true);self.key:SetPassControlToScreen(CONTROL_CANCEL,true)
 self.status=self.root:AddChild(Text(TALKINGFONT,20,'检查本机后台……'));self.status:SetRegionSize(700,105);self.status:EnableWordWrap(true);self.status:SetPosition(0,-65)
 self.save=button(self.root,'保存密钥',-240,function()self:Save()end)
 self.test=button(self.root,'测试连接',-80,function()self:Test()end)
 self.retry=button(self.root,'重试连接',80,function()self:Connect()end)
 self.close=button(self.root,'关闭',240,function()self:Close()end)
 self.default_focus=self.key;self:StartUpdating();self:Connect()
end)
function Config:Message(s)if not self.closed then self.status:SetString(s) end end
function Config:Request(path,body,cb)
 self.requestseq=self.requestseq+1;local serial=self.requestseq;self.requestdeadline=self.clock+8
 local raw=body and json.encode_compliant(body) or nil
 local ok=pcall(function()TheSim:QueryServer('http://127.0.0.1:8765'..path,function(result,success,code)
  if self.closed or serial~=self.requestseq then return end
  self.requestdeadline=nil
  local decoded,d=pcall(json.decode,result or '')
  if not success or not decoded or type(d)~='table' then self.busy=false;self.testid=nil;self.polling=false;self:Message('无法连接本机后台，请运行新版 start_ai.cmd，再点重试连接。');return end
  cb(d,code)
 end,body and 'POST' or 'GET',raw)end)
 if not ok then self.requestdeadline=nil;self.busy=false;self.testid=nil;self.polling=false;self:Message('无法连接，请启动本机后台后重试。') end
end
function Config:Connect()
 if self.busy then return end
 self.busy=true;self.token=nil;self:Message('检查本机后台……')
 self:Request('/config/status',nil,function(d,code)
  self.busy=false
  if code~=200 or not d.token then self:Message('后台版本不支持配置，请运行本包的新版 start_ai.cmd。');return end
  self.token=d.token;self.ai=d.ai_mode
  self:Message((d.configured and '已有密钥（不会回读显示）；可直接测试或输入新密钥更换。' or '尚未配置，请粘贴密钥后保存。')..(self.ai and '' or '\n当前是模拟后台，请关闭它并运行 start_ai.cmd。'))
 end)
end
function Config:Save()
 if self.busy then return end
 if not self.token then self:Message('请先启动新版后台，点击重试连接。');return end
 local key=self.key:GetLineEditString():match('^%s*(.-)%s*$')
 if #key<10 then self:Message('请输入完整 API 密钥。');return end
 self.busy=true;self.key:SetString('');self.key:SetEditing(false);self:Message('保存中……')
 self:Request('/config/save',{token=self.token,key=key},function(d,code)
  self.busy=false
  self:Message(code==200 and '已保存到本机后台；请点击测试连接。' or '保存失败，请检查密钥格式及后台目录写入权限后重试。')
 end)
end
function Config:Test()
 if self.busy then return end
 if not self.token then self:Message('请先连接本机后台。');return end
 self.busy=true;self.elapsed=0;self.testid=nil;self.timer=0;self.polling=false;self:Message('正在测试（会产生一次很短的模型请求费用）……')
 self:Request('/config/test',{token=self.token},function(d,code)
  if code==200 and d.test_id then self.testid=d.test_id;return end
  self.busy=false;self:Message(d.error=='missing_key' and '请先保存密钥。' or '暂时不能测试，请稍后重试；后台重启后请先重试连接。')
 end)
end
function Config:OnUpdate(dt)
 self.clock=self.clock+dt
 if self.requestdeadline and self.clock>=self.requestdeadline then
  self.requestseq=self.requestseq+1;self.requestdeadline=nil;self.testid=nil;self.polling=false;self.busy=false
  self:Message('本机后台连接超时，请确认新版后台已启动后重试。');return
 end
 if not self.testid then return end
 self.elapsed=self.elapsed+dt;self.timer=self.timer+dt
 if self.elapsed>30 then self.testid=nil;self.busy=false;self:Message('测试等待超时，可重试；后台的本次网络调用可能仍在结束。');return end
 if self.timer<2 or self.polling then return end
 self.timer=0;self.polling=true
 local id=self.testid
 self:Request('/config/test/'..id,nil,function(d,code)
  self.polling=false;if self.testid~=id then return end
  if d.state=='pending' then return end
  self.testid=nil;self.busy=false
  if code==200 and d.state=='done' then
   self:Message(string.format('连接成功：%.2f 秒，输入 %d / 输出 %d / 总计 %d tokens。',d.elapsed_ms/1000,d.prompt_tokens,d.completion_tokens,d.total_tokens))
  else
   local errors={invalid_key='密钥无效，请更换后保存。',balance='账户额度不足，请检查 DeepSeek 余额。',rate_limit='服务限流，请稍后再试。'}
   self:Message(errors[d.error] or '测试失败，请检查网络及账户；后台重启后先重试连接。')
  end
 end)
end
function Config:Close()self.closed=true;self.key:SetString('');self.key:SetEditing(false);self.token=nil;TheFrontEnd:PopScreen(self)end
function Config:OnControl(c,down)if not down and c==CONTROL_CANCEL then self:Close();return true end;Config._base.OnControl(self,c,down);return true end
function Config:OnRawKey(k,d)Config._base.OnRawKey(self,k,d);return true end
return Config
