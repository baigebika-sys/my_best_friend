-- Bounded task engine, injected world/action adapter; reusable for future work types.
local M={}
function M.New(o)
 local self={job=nil,sequence=0}
 local function describe(j,reason)
  if o.describe then return o.describe(j,reason) end
  local text="捡到了"..j.count.."个"..j.label
  if j.goal and j.count<j.goal then text=text.."，还差"..(j.goal-j.count).."个" end
  return text.."；"..reason
 end
 function self:End(reason,restore,advance)
  local j=self.job;if not j then return end
  if o.refresh then o.refresh(j) end
  j.attempt=(j.attempt or 0)+1
  j.inflight=false
  o.stop()
  j.results[#j.results+1]=describe(j,reason)
  j.records[#j.records+1]={kind=j.kind,item=j.item,goal=j.goal,count=j.count,reason=reason,
   reached_goal=j.goal~=nil and j.count>=j.goal and not j.fatal and (not o.complete or o.complete(j)),audit=j.audit}
  if advance and j.plan and j.index<#j.plan then
   j.index=j.index+1;local nextitem=j.plan[j.index]
   j.item=nextitem.item;j.goal=nextitem.goal;j.label=nextitem.label;j.count=0
   j.kind=nextitem.kind or j.kind;j.prepare=nextitem.prepare;j.ensure=nextitem.ensure;j.workdone=nil;j.treeclean=nil;j.audit=nil;j.material=nil;j.collectitem=nil;j.autotool=nil;j.recipe=nil;j.invobject=nil;j.awaitloot_until=nil;j.fatal=nil
   if nextitem.kind then j.deadline=o.now()+o.timeout end
   j.failed={};j.inflight=false;j.target=nil;j.step=nil;j.preferred=nil;j.settle_until=nil
   -- Invalidate callbacks from the preceding item as well as preceding tasks.
   self.sequence=self.sequence+1;j.serial=self.sequence
   return
  end
  if j.plan then
   for index=j.index+1,#j.plan do
    local entry=j.plan[index]
    j.results[#j.results+1]=describe({count=0,label=entry.label,goal=entry.goal},"未开始："..reason)
    j.records[#j.records+1]={kind=entry.kind,item=entry.item,goal=entry.goal,count=0,reason="未开始："..reason,reached_goal=false}
   end
  end
  self.job=nil;self.sequence=self.sequence+1
  o.report(table.concat(j.results,"。"),j)
  if restore then o.restore(j.previous,j.anchor) end
 end
 function self:Start(item,goal,label,plan)
  local previous,anchor=o.capture()
  if self.job then previous=self.job.previous;anchor=self.job.anchor;self:End("被新任务替代",false) end
  self.sequence=self.sequence+1
  self.job={item=item,goal=goal,label=label,count=0,center=o.position(),previous=previous,anchor=anchor,
   deadline=o.now()+o.timeout,failed={},id=self.sequence,serial=self.sequence,plan=plan,index=1,results={},records={}}
  o.enter();return true
 end
 function self:Count(token,n)
  local j=self.job;if j and j.serial==token then j.count=j.count+math.max(0,n) end
 end
 function self:Tick(continuous)
  local j=self.job;if not j then return end
  if o.refresh then o.refresh(j) end
  if j.blocked then return end
  if j.fatal then
   if j.kind=='goal' and o.block then o.block(j,j.fatal,j.uncertain and 'unverified_result' or 'execution_condition') else self:End(j.fatal,true) end
   return
  end
  if j.goal and j.count>=j.goal and (not o.complete or o.complete(j)) then self:End("已达到目标数量",true,true);return end
  if o.now()>=j.deadline then
   if j.kind=='goal' and o.block then o.block(j,"达到本轮工作时间上限",'task_timeout') else self:End("达到任务时间上限",true) end
   return
  end
  if j.inflight then
   if not o.valid(j.target,j.center,j) or o.now()>=j.attemptdeadline then
    j.attempt=(j.attempt or 0)+1
    o.stop();j.failed[j.target]=(j.failed[j.target] or 0)+1;j.inflight=false
   else return end
  end
  if not continuous and (o.busy() or j.settle_until and o.now()<j.settle_until) then return end
  local target,reason,code=o.find(j)
  if not target and code=="pending" then return end
  if not target then
   if j.kind=='goal' and o.block and code~='complete' then o.block(j,reason or "范围内没有更多可用目标",code)
   else self:End(reason or "范围内没有更多可用目标",true,code=="exhausted" or code=='complete') end
   return
  end
  j.attempt=(j.attempt or 0)+1
  local attempt=j.attempt
  j.target=target;j.inflight=true;j.attemptdeadline=o.now()+(o.actiontime and o.actiontime(target,j) or 8)
  local token=j.serial
  o.pickup(target,token,attempt,function(success)
   if self.job~=j or j.serial~=token or j.target~=target or j.attempt~=attempt then return end
   j.inflight=false
   j.settle_until=o.now()+(o.settle or 0)
   if not success then j.failed[target]=(j.failed[target] or 0)+1 end
  end)
 end
 return self
end
return M
