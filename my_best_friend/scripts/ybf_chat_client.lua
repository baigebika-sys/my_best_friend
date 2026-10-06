local Store=require("ybf_chat_store")
local M={store=Store.New()}
function M.Reset()M.store=Store.New()end
function M.ClearWaiting()M.store.pending={};M.store.notice="";M.store.revision=M.store.revision+1 end
function M.Send(text,name,fromslash,targetguid)
 text=type(text)=="string" and text:match("^%s*(.-)%s*$") or ""
 name=type(name)=="string" and name:match("^%s*(.-)%s*$") or ""
 if not ThePlayer or text=="" or #text>600 or #name>120 then
  M.store.notice="请输入正文（最多600字节，约200个汉字）。";M.store.revision=M.store.revision+1;return false
 end
 M.store.last_sent={text=text,name=name}
 local selected
 if name=="" then
  for _,f in ipairs(M.store.friends or {}) do if f.guid==(targetguid or M.store.selected) then selected=f;break end end
  if selected then name=selected.name end
 end
 if targetguid and not selected then M.store.notice="原来的朋友已不可用，请重新选择。";M.store.revision=M.store.revision+1;return false end
 M.store.last_sent={text=text,name=selected and "" or name,guid=selected and selected.guid}
 local tag=M.store:Outgoing(name,text)
 if fromslash then M.open_on_error=tag end
 local ok=pcall(function()SendModRPCToServer(GetModRPC("my_best_friend","send"),text,name,tag,selected and selected.guid)end)
 if not ok then M.store:Event({kind="error",tag=tag,id="local-error-"..tag,text="暂时无法发送，请重新打开窗口再试。"}) end
 return ok
end
function M.Retry()
 local last=M.store.last_sent
 if last then return M.Send(last.text,last.name,false,last.guid) end
 M.store.notice="还没有可重试的消息。";M.store.revision=M.store.revision+1;return false
end
function M.RequestRoster()
 if ThePlayer then pcall(function()SendModRPCToServer(GetModRPC("my_best_friend","roster"))end) end
end
function M.Receive(raw)
 if type(raw)~="string" or #raw>12000 then return end
 local ok,d=pcall(json.decode,raw)
 if not ok or type(d)~="table" then return end
 if d.kind=="roster" then
  local incoming=d.friends or {};local old=M.store.friends or {};local changed=#old~=#incoming
  for i,f in ipairs(incoming) do if not old[i] or old[i].guid~=f.guid or old[i].name~=f.name then changed=true end end
  if not changed then return end
  M.store.friends=incoming;local found=false
  for _,f in ipairs(M.store.friends) do if f.guid==M.store.selected then found=true end end
  if not found then M.store.selected=#M.store.friends==1 and M.store.friends[1].guid or nil end
  M.store.revision=M.store.revision+1;return
 end
 M.store:Event(d)
 if d.kind=="error" and d.tag==M.open_on_error then
  M.open_on_error=nil
  M.store.draft=M.store.last_sent and M.store.last_sent.text or ""
  local active=TheFrontEnd:GetActiveScreen()
  if not active or active.name~="YBFChatScreen" then TheFrontEnd:PushScreen(require("screens/ybf_chatscreen")()) end
 end
end
return M
