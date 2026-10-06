-- Pure local policy. Future personalities may replace weights without changing executors.
local M={keys={"hunger","health","sanity"}}
M.defaults={hunger={trigger=.40,target=.80,weight=1},health={trigger=.70,target=.90,weight=3},sanity={trigger=.40,target=.75,weight=2}}
function M.Update(flags,stats,rules)
 for _,key in ipairs(M.keys) do
  local s=stats[key];local r=rules[key]
  if s and s.maximum>0 then
   local p=s.current/s.maximum
   if flags[key] then if p>=r.target then flags[key]=false end
   elseif p<=r.trigger then flags[key]=true end
  else flags[key]=false end
 end
end
function M.Score(candidate,stats,flags,rules)
 if not candidate.supported or not candidate.known or candidate.unsafe then return nil end
 local score=0;local useful=false
 for _,key in ipairs(M.keys) do
  local amount=candidate.effects[key] or 0
  if amount<0 then return nil end -- no emergency relaxation
  local s=stats[key]
  if s and s.maximum>0 then
   local gain=math.min(amount,math.max(0,s.maximum-s.current))
   if flags[key] then
    local needed=math.max(0,rules[key].target*s.maximum-s.current)
    local used=math.min(gain,needed)
    if used>0 then useful=true end
    score=score+rules[key].weight*used/s.maximum
   end
   score=score-.05*math.max(0,amount-gain)/s.maximum
  end
 end
 return useful and score>0 and score or nil
end
return M
