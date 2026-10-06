-- Selected unmodified vanilla action functions; upstream URLs in reference_sources.md.

local function DoToolWork(act, workaction)
    if act.target.components.workable ~= nil and
        act.target.components.workable:CanBeWorked() and
        act.target.components.workable:GetWorkAction() == workaction and
        (act.invobject == nil or act.doer == nil or act.invobject.components.equippable == nil or not act.invobject.components.equippable:IsRestricted(act.doer))
    then
        if ShouldItemMimicBeRevealedFor(act.invobject, act.doer) then
            return false, "ITEMMIMIC"
        end

		local numworks =
			(	(	act.invobject ~= nil and
					act.invobject.components.tool ~= nil and
					act.invobject.components.tool:GetEffectiveness(workaction)
				) or
				(	act.doer ~= nil and
					act.doer.components.worker ~= nil and
					act.doer.components.worker:GetEffectiveness(workaction)
				) or
				1
			) *
			(	act.doer.components.workmultiplier ~= nil and
				act.doer.components.workmultiplier:GetMultiplier(workaction) or
				1
			)

		local recoil
		recoil, numworks = act.target.components.workable:ShouldRecoil(act.doer, act.invobject, numworks)

		if act.doer.components.workmultiplier ~= nil then
			numworks = act.doer.components.workmultiplier:ResolveSpecialWorkAmount(workaction, act.target, act.invobject, numworks, recoil)
		end

		if recoil and act.doer.sg ~= nil and act.doer.sg.statemem.recoilstate ~= nil then
            act.doer:PushEventImmediate("recoil_off", { target = act.target } )
			if numworks == 0 then
				act.doer:PushEvent("tooltooweak", { workaction = workaction })
			end
		end
		--V2C: Call the "internal" function directly since we've already accounted for recoil.
		--     Chose the "internal" naming to discourage more places from calling it directly.
		act.target.components.workable:WorkedBy_Internal(act.doer, numworks)
        return true
    end
    return false
end

local function ValidToolWork(act, workaction)
    return
        act.target.components.workable ~= nil and
        act.target.components.workable:CanBeWorked() and
        act.target.components.workable:GetWorkAction() == workaction and
        (act.invobject == nil or act.doer == nil or act.invobject.components.equippable == nil or not act.invobject.components.equippable:IsRestricted(act.doer))
end

ACTIONS.CHOP.fn = function(act)
    local work_success, work_fail_reason = DoToolWork(act, ACTIONS.CHOP)
    if work_success and
            act.doer ~= nil and
            act.doer.components.spooked ~= nil and
            act.target:IsValid() then
        act.doer.components.spooked:Spook(act.target)
    end
    if not work_success and work_fail_reason ~= nil then
        return false, work_fail_reason
    else
        return true
    end
end

ACTIONS.CHOP.validfn = function(act)
    return ValidToolWork(act, ACTIONS.CHOP)
end

ACTIONS.MINE.fn = function(act)
    local work_success, work_fail_reason = DoToolWork(act, ACTIONS.MINE)
    if not work_success and work_fail_reason ~= nil then
        return false, work_fail_reason
    else
        return true
    end
end

ACTIONS.MINE.validfn = function(act)
    return ValidToolWork(act, ACTIONS.MINE)
end

ACTIONS.PICK.fn = function(act)
    if act.target ~= nil then
        if act.target.components.pickable ~= nil then
			if act.target.components.pickable:IsStuck() then
				return false, "STUCK"
			end
            act.target.components.pickable:Pick(act.doer)
            return true
        elseif act.target.components.searchable ~= nil then
            return act.target.components.searchable:Search(act.doer)
        end
    end
end

ACTIONS.PICK.validfn = function(act)
    return act.target
        and (
            (act.target.components.pickable and act.target.components.pickable:CanBePicked())
            or (act.target.components.searchable and act.target.components.searchable.canbesearched)
        )
end

ACTIONS.GIVETOPLAYER.fn = function(act)
    if ShouldBlockGiving(act) then
        return false
    end

    if act.target ~= nil and
            act.target.components.trader ~= nil and
            act.target.components.inventory ~= nil and
            (act.target.components.inventory:IsOpenedBy(act.target) or act.target:HasTag("playerghost")) then
        if act.target.components.inventory:CanAcceptCount(act.invobject, 1) <= 0 then
            return false, "FULL"
        end
        local able, reason = act.target.components.trader:AbleToAccept(act.invobject, act.doer)
        if not able then
            return false, reason
        else
            act.target.components.trader:AcceptGift(act.doer, act.invobject, 1)
            return true
        end
    end
end

ACTIONS.BUILD.fn = function(act)
    if act.doer.components.builder ~= nil then
        return act.doer.components.builder:DoBuild(act.recipe, act:GetActionPoint(), act.rotation, act.skin)
    end
end
