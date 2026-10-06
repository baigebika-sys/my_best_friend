-- Native stategraph actions run outside Work:Tick. Keep their errors inside
-- this friend's task; never alter exception behavior for human players.
local M={}
local function traceback(err)
 return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err)
end
function M.Run(work,phase,fn)
 local ok,a,b=xpcall(fn,traceback)
 if ok then return true,a,b end
 -- Stop/invalidate before further native callbacks can observe this attempt.
 local handled,err=pcall(work.ExecutionError,work,'phase='..phase..'\n'..tostring(a))
 if not handled then
  print('[YBF WORK] error_cleanup_failed: '..tostring(err))
  local j=work.core and work.core.job
  if j then j.attempt=(j.attempt or 0)+1;j.inflight=false;j.fatal='工作出现异常，已停止';j.blocked={code='cleanup_error',reason=j.fatal};j.nonresumable=true end
 end
 return false
end
function M.Action(work,act)
 local original=act.Do
 act.Do=function(action)
  local ok,result,reason=M.Run(work,'native_action_'..tostring(action.action.id),function()return original(action)end)
  if ok then return result,reason end
  return false,'YBF_WORK_ERROR'
 end
end
function M.Timeline(sg)
 for _,name in ipairs({'chop','mine'}) do
  local state=sg.states[name]
  if state then
   for _,event in ipairs(state.timeline or {}) do
    local original=event.fn
    local phase='state_'..name..'_frame_'..tostring(event.time)
    event.fn=function(inst)
     local work=inst.components.ybf_work
     local friend=inst.components.ybf_friend
     if work and friend and friend.active then
      M.Run(work,phase,function()return original(inst)end)
     else return original(inst) end
    end
   end
  end
 end
end
function M.Install(sg,G)
 M.Timeline(sg)
 for _,name in ipairs({'chop','mine'}) do
  local state=sg.states[name]
  if state then
   local step=name
   table.insert(state.timeline,G.TimeEvent(14*G.FRAMES,function(inst)
    local work=inst.components.ybf_work
    local friend=inst.components.ybf_friend
    if work and friend and friend.active then
     M.Run(work,'repeat_'..step,function()return work:ContinueSwing(step)end)
    end
   end))
   table.sort(state.timeline,function(a,b)return a.time<b.time end)
  end
 end
end
return M
