local M={}
function M.Emit(G,player,d)
 if not player or not player.userid then return end
 local ok=pcall(function()G.SendModRPCToClient(G.GetClientModRPC("my_best_friend","event"),player.userid,G.json.encode_compliant(d))end)
 if not ok then print("[YBF UI] client notification unavailable") end
end
function M.ErrorText(status,detail)
 if status=="parse_error" or status=="execution_blocked" then return detail or (status=="parse_error" and "[指令解析失败] 未下发工作动作。" or "[游戏执行受阻] 已保留现有物品。") end
 if status=="timeout" then return "朋友这次没有及时回答，请重新发送。" end
 if status=="shutdown" then return "世界已关闭，已停止等待。" end
 return "暂时无法联系朋友。房主请确认后台已启动、密钥可用，再重新发送。"
end
function M.New(G,world,communication)
 local self={seen={},order={},sequence=0}
 function self:Send(player,text,name,tag,guid)
  if not player or not player:IsValid() or player:HasTag("ybf_friend") then return end
  if type(tag)~="string" or #tag>80 or not tag:match("^[%w%-]+$") then return end
  local key=(player.userid or tostring(player.GUID))..":"..tag
  if self.seen[key] then return end
  self.seen[key]=true;self.order[#self.order+1]=key
  if #self.order>256 then local old=table.remove(self.order,1);self.seen[old]=nil end
  self.sequence=self.sequence+1
  local function reject(reason)
   print("[YBF UI] send rejected: "..reason)
   M.Emit(G,player,{kind="error",tag=tag,id=tostring(world.GUID).."-reject-"..self.sequence,text=reason})
  end
  if type(text)~="string" or #text==0 or #text>600 then reject("请输入正文（最多600字节）。");return end
  if type(name)~="string" or #name>120 then reject("朋友名字太长，请重新填写。");return end
  name=name:match("^%s*(.-)%s*$")
  local ctx,reason=communication.Context(G,player,name~="" and name or nil,type(guid)=="number" and guid or nil)
  if not ctx then
   reject(reason:find("多位") and "有多位朋友，请在聊天窗口顶部选择对象；也可用 /friend 朋友名字|你好。" or "没有找到对应朋友，请确认持有他的友谊小花且朋友还活着。")
   return
  end
  ctx.clienttag=tag
  local direct=text:match("^%s*(.-)%s*$")
  if direct=="停止任务" or direct=="停止工作" then
   local core=world._ybf_communication
   if core then
    local ids={};for id,pending in pairs(core.pending) do if pending.friend==ctx.friend then ids[#ids+1]=id end end
    for _,id in ipairs(ids) do core:Cancel(id,"停止指令取消旧请求") end
   end
   local work=ctx.friend.components.ybf_work
   local needs=ctx.friend.components.ybf_needs
   if needs then needs:CancelExplicit() end
   if work then work:Cancel(true) end
   M.Emit(G,player,{kind="reply",tag=tag,id=tostring(world.GUID).."-stop-"..self.sequence,name=ctx.name,text="好，我已停止任务，保留物品并恢复原来的安排。"})
   return
  end
  if not world._ybf_communication then world._ybf_communication=communication.New(G,world) end
  local ok,detail=world._ybf_communication:Send(ctx,text)
  if not ok then reject(detail=="发送太快，请稍等半秒" and "发送太快，请稍等片刻。" or "暂时无法发送，请稍后重试。") end
 end
 return self
end
return M
