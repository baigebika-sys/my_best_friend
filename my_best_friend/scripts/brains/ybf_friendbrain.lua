-- 复用原版切斯特 Follow 行为与距离；不添加战斗/采集/闲逛指令。
require "behaviours/follow"
require "behaviours/faceentity"
require "behaviours/standstill"
local WorkBusy=Class(BehaviourNode,function(self,inst)BehaviourNode._ctor(self,"WorkBusy");self.inst=inst end)
function WorkBusy:Visit()self.status=RUNNING end
local function GetTarget(inst)
    if not inst.components.ybf_friend:AllowsOwnerMovement() then return nil end
    local flower = inst.components.ybf_friend.flower
    if flower == nil or not flower:IsValid() then return nil end
    return flower.components.inventoryitem:GetGrandOwner() or flower
end
local function IsTrading(inst)
    local target = GetTarget(inst)
    local action = target and target.GetBufferedAction and target:GetBufferedAction()
    return action ~= nil and action.target == inst
end
local FriendBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)
function FriendBrain:OnStart()
    self.bt = BT(self.inst, PriorityNode({
        WhileNode(function() return self.inst.components.ybf_work and self.inst.components.ybf_work:IsBusy() end,"Task controls movement",WorkBusy(self.inst)),
        WhileNode(function() return self.inst.sg:HasStateTag("busy") or self.inst:GetBufferedAction() ~= nil end, "Finish action", StandStill(self.inst)),
        WhileNode(function() return IsTrading(self.inst) end, "Wait for player", StandStill(self.inst)),
        Follow(self.inst, GetTarget, 0, 6, 12),
        FaceEntity(self.inst, GetTarget, function(inst, target) return target == GetTarget(inst) end),
        StandStill(self.inst),
    }, 0.25))
end
return FriendBrain
