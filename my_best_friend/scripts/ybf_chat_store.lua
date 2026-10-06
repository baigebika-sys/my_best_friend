-- UI history is independent of model memory; bounded and deduplicated by transport IDs.
local M={}
function M.New()
 local self={rows={},pending={},seen={},seenorder={},sequence=0,bytes=0,revision=0,notice="",draft="",target=""}
 function self:Add(id,kind,name,text,tag)
  if type(id)~="string" or type(text)~="string" then return false end
  if self.seen[id] then return false end
  self.seen[id]=true;self.seenorder[#self.seenorder+1]=id
  if #self.seenorder>512 then local old=table.remove(self.seenorder,1);self.seen[old]=nil end
  local row={id=id,kind=kind,name=name or "朋友",text=text or "",tag=tag}
  row.bytes=#row.name+#row.text
  self.rows[#self.rows+1]=row;self.bytes=self.bytes+row.bytes
  while #self.rows>200 or self.bytes>40000 do local old=table.remove(self.rows,1);self.bytes=self.bytes-old.bytes end
  self.revision=self.revision+1;return true
 end
 function self:Outgoing(name,text)
  self.sequence=self.sequence+1;local tag="ui-"..self.sequence
  self:Add("player-"..tag,"player",name~="" and name or "朋友",text,tag)
  self.pending[tag]=true;self.notice="";self.revision=self.revision+1;return tag
 end
 function self:Event(d)
  if type(d)~="table" or type(d.kind)~="string" then return end
  if d.kind=="sent" then
   for _,row in ipairs(self.rows) do
    if row.tag==d.tag then self.bytes=self.bytes-row.bytes;row.name=d.name or row.name;row.bytes=#row.name+#row.text;self.bytes=self.bytes+row.bytes;break end
   end
  elseif d.kind=="reply" or d.kind=="feedback" then
   self:Add(d.id,d.kind,d.name,d.text)
   if d.tag then self.pending[d.tag]=nil end
   self.notice=""
  elseif d.kind=="error" then
   if d.tag then self.pending[d.tag]=nil end
   self.notice=d.text or "暂时无法发送，请稍后重试。"
   self:Add(d.id,"error","提示",self.notice)
  elseif d.kind=="cancelled" then
   if d.tag then self.pending[d.tag]=nil end
   self.notice="已停止等待，旧回复不会显示。"
  elseif d.kind=="accepted" then
   -- Waiting is UI-only, never a public announcement or model memory entry.
  end
  while #self.rows>200 or self.bytes>40000 do local old=table.remove(self.rows,1);self.bytes=self.bytes-old.bytes end
  self.revision=self.revision+1
 end
 function self:Status()
  local count=0;for _ in pairs(self.pending) do count=count+1 end
  return count>0 and "朋友正在想怎么回答……" or self.notice
 end
 return self
end
function M.Preview(text,limit)
 local ends={};local i=1
 while i<=#text do
  local byte=text:byte(i);local width=byte<128 and 1 or byte<224 and 2 or byte<240 and 3 or 4
  i=i+width;ends[#ends+1]=i-1
 end
 if #ends<=limit then return text end
 return text:sub(1,ends[limit]).."…"
end
return M
