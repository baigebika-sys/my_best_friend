-- Pure async state machine; no direct network/file access.
local M = {}
function M.New(o)
    local self = {pending={},count=0,sequence=0,closed=false,lastsend={}}
    local function cancel_external(r)
        if r.taskid and r.instance and not r.cancel_sent and o.cancel then
            r.cancel_sent=true
            pcall(o.cancel,r.taskid,r.instance)
        end
    end
    local function finish(r,status,detail,reply)
        if self.pending[r.id]~=r then return end
        self.pending[r.id]=nil;self.count=self.count-1;r.ended=status
        if status~="reply" then cancel_external(r) end
        if o.unwatch then o.unwatch(r) end
        local ms=math.max(0,(o.now()-r.started)*1000)
        o.log(r.id,status,ms,detail)
        if status~="shutdown" then o.notify(r,status,ms,detail,reply) end
    end
    local function decode(response)
        if type(response)~="string" or #response>4096 then return nil end
        local ok,d=pcall(o.decode,response)
        if ok and type(d)=="table" then return d end
    end
    local function identity(r,d)
        return d and d.protocol=="ybf-task-v1" and d.request_id==r.id
            and d.friend_id==tostring(r.friend.GUID) and d.task_id==r.id
            and type(d.instance_id)=="string" and #d.instance_id==32
            and d.instance_id:match("^[a-f0-9]+$")
    end
    local dispatch
    dispatch=function(r,kind)
        r.serial=(r.serial or 0)+1
        local serial=r.serial
        r.inflight=true;r.httpdeadline=o.now()+o.http_timeout
        local function cb(response,success,code)
            if serial~=r.serial or not r.inflight then return end
            r.inflight=false
            local d=decode(response)
            if self.closed or self.pending[r.id]~=r then
                -- Submit may finish after cancellation, before its task id was known.
                if kind=="submit" and success and (code==200 or code==202) and identity(r,d) then
                    r.taskid=d.task_id;r.instance=d.instance_id;cancel_external(r)
                end
                o.log(r.id,"ignored_late",math.max(0,(o.now()-r.started)*1000),"request ended")
                return
            end
            if not o.valid(r) then finish(r,"cancelled","朋友死亡、被移除或持有人离开；已停止等待");return end
            if o.now()>=r.deadline then finish(r,"timeout","游戏任务等待超时（45 秒）；旧结果将丢弃");return end
            if o.now()>=r.httpdeadline then finish(r,"error","连接层等待超时（8 秒）；任务等待结束");return end
            if kind=="poll" and success and code==409 then finish(r,"error","外部程序已重启；旧任务失效，请重新发送");return end
            if kind=="poll" and success and code==404 then finish(r,"error","外部任务已过期或不存在，请重新发送");return end
            if not success or (code~=200 and not (kind=="submit" and code==202)) then
                finish(r,"error","连接层失败（HTTP "..tostring(code).."）；请检查程序并重新发送");return
            end
            if not identity(r,d) or (r.instance and r.instance~=d.instance_id) then
                finish(r,"error","任务编号、朋友或程序会话不匹配，拒绝显示");return
            end
            r.taskid=d.task_id;r.instance=d.instance_id
            if d.state=="done" then
                if type(d.reply)~="string" or #d.reply==0 or #d.reply>600 then finish(r,"error","回复格式错误");return end
                local reply=d.reply
                if o.apply then
                    if d.action~="wait" and d.action~="follow" and d.action~="none" and d.action~="pickup" and d.action~="stop" and d.action~="eat" and d.action~="collect" and d.action~="craft" and d.action~="give" and d.action~="plan" and d.action~="goal" and d.action~="resume" and d.action~="equip" then finish(r,"parse_error","[指令解析失败] 模型动作格式错误，未下发工作动作");return end
                    local ok,result=pcall(o.apply,r,d.action,reply,d)
                    if not ok or type(result)~="string" then finish(r,"execution_blocked","[游戏执行受阻] 指令已解析，但动作接入失败，未确认完成");return end
                    reply=result
                end
                finish(r,"reply","task completed",reply)
            elseif d.state=="pending" then
                r.nextpoll=o.now()+o.poll_interval
                if kind=="submit" then o.notify(r,"accepted",(o.now()-r.started)*1000,"任务已提交；后台处理中，每 2 秒查询结果") end
            elseif d.state=="timeout" then finish(r,"timeout","外部任务处理超时；请重新发送")
            elseif d.state=="error" then
                local diagnostic=d.diagnostic
                if type(diagnostic)=='table' and (diagnostic.category=='decision_json' or diagnostic.category=='decision_schema' or diagnostic.category=='provider_json' or diagnostic.category=='provider_envelope') then
                    local reason=type(diagnostic.reason)=='string' and diagnostic.reason:sub(1,360) or '返回结构不合法'
                    local code=type(diagnostic.code)=='string' and diagnostic.code:match('^[a-z_]+$') and diagnostic.code or 'invalid_result'
                    finish(r,'parse_error','[指令解析失败] '..code..'：'..reason..'；未下发工作动作')
                else finish(r,"error","模型调用失败；请检查后台连接状态后重新发送") end
            elseif d.state=="cancelled" then finish(r,"cancelled","外部任务已取消")
            else finish(r,"error","未知任务状态") end
        end
        local ok
        if kind=="submit" then ok=pcall(o.query,r.body,cb)
        else ok=pcall(o.poll,r.taskid,r.instance,cb) end
        if not ok then r.inflight=false;finish(r,"error","游戏通信接口调用失败") end
    end
    function self:Cancel(id,reason)
        local r=self.pending[id];if r then finish(r,"cancelled",reason or "已停止等待") end
    end
    function self:Tick()
        local all={};for _,r in pairs(self.pending) do all[#all+1]=r end
        for _,r in ipairs(all) do
            if self.pending[r.id]==r then
                if not o.valid(r) then finish(r,"cancelled","朋友死亡、被移除或持有人离开；请求已取消")
                elseif o.now()>=r.deadline then finish(r,"timeout","游戏任务等待超时（45 秒）；旧结果将丢弃")
                elseif r.inflight and o.now()>=r.httpdeadline then finish(r,"error","连接层等待超时（8 秒）；任务等待结束")
                elseif not r.inflight and r.nextpoll and o.now()>=r.nextpoll then dispatch(r,"poll") end
            end
        end
    end
    function self:Close()
        self.closed=true
        local all={};for _,r in pairs(self.pending) do all[#all+1]=r end
        for _,r in ipairs(all) do finish(r,"shutdown","世界关闭") end
        self.lastsend={}
    end
    function self:Send(ctx,text)
        if self.closed then return false,"世界正在关闭" end
        if self.count>=8 then return false,"等待中的任务过多，请稍后再试" end
        if type(text)~="string" or #text==0 or #text>600 then return false,"消息必须为 1 至 600 字节" end
        if not o.valid(ctx) then return false,"朋友已离开或死亡" end
        local now=o.now()
        if self.lastsend[ctx.playerkey] and now-self.lastsend[ctx.playerkey]<0.5 then return false,"发送太快，请稍等半秒" end
        local obsolete={}
        for id,old in pairs(self.pending) do if old.friend==ctx.friend then obsolete[#obsolete+1]=id end end
        for _,id in ipairs(obsolete) do self:Cancel(id,"新消息覆盖旧请求；旧结果将丢弃") end
        self.lastsend[ctx.playerkey]=now;self.sequence=self.sequence+1
        local r={id=o.session.."-"..tostring(self.sequence),friend=ctx.friend,flower=ctx.flower,player=ctx.player,
            clienttag=ctx.clienttag,text=text,playerkey=ctx.playerkey,name=ctx.name,playername=ctx.playername,started=now,deadline=now+o.timeout}
        local ok,body=pcall(function() return o.encode({protocol="ybf-task-v1",request_id=r.id,friend_id=tostring(r.friend.GUID),friend_name=r.name,message=text,conversation_id=o.session,game_state=o.snapshot and o.snapshot(ctx) or nil}) end)
        if not ok then return false,"请求编码失败" end
        r.body=body;self.pending[r.id]=r;self.count=self.count+1
        if o.watch then o.watch(r,function(reason)self:Cancel(r.id,reason)end) end
        o.notify(r,"sent",0,"正在提交后台任务")
        o.log(r.id,"sent",0,"submit queued");dispatch(r,"submit")
        return true,r.id
    end
    return self
end
return M
