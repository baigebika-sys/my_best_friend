-- Native SGwilson chop/mine excerpts from existing engine_reference.
-- Loaded with mocked animation/network in tests; not an engine run.
return {
    State{
        name = "chop",
        tags = { "prechop", "chopping", "working" },

        onenter = function(inst)
            inst.sg.statemem.action = inst:GetBufferedAction()
            inst.sg.statemem.iswoodcutter = inst:HasTag("woodcutter")
            inst.AnimState:PlayAnimation(inst.sg.statemem.iswoodcutter and "woodie_chop_loop" or "chop_loop")
			inst:AddTag("prechop")
        end,

        timeline =
        {
            ----------------------------------------------
            --Woodcutter chop

            TimeEvent(2 * FRAMES, function(inst)
                if inst.sg.statemem.iswoodcutter then
                    inst:PerformBufferedAction()
                end
            end),

            TimeEvent(5 * FRAMES, function(inst)
                if inst.sg.statemem.iswoodcutter then
                    inst.sg:RemoveStateTag("prechop")
					inst:RemoveTag("prechop")
                end
            end),

            TimeEvent(10 * FRAMES, function(inst)
                if inst.sg.statemem.iswoodcutter and
                    inst.components.playercontroller ~= nil and
                    inst.components.playercontroller:IsAnyOfControlsPressed(
                        CONTROL_PRIMARY,
                        CONTROL_ACTION,
                        CONTROL_CONTROLLER_ACTION) and
                    inst.sg.statemem.action ~= nil and
                    inst.sg.statemem.action:IsValid() and
                    inst.sg.statemem.action.target ~= nil and
                    inst.sg.statemem.action.target.components.workable ~= nil and
                    inst.sg.statemem.action.target.components.workable:CanBeWorked() and
                    inst.sg.statemem.action.target:IsActionValid(inst.sg.statemem.action.action) and
                    CanEntitySeeTarget(inst, inst.sg.statemem.action.target) then
					--No fast-forward when repeat initiated on server
					inst.sg.statemem.action.options.no_predict_fastforward = true
                    inst:ClearBufferedAction()
                    inst:PushBufferedAction(inst.sg.statemem.action)
                end
            end),

            TimeEvent(12 * FRAMES, function(inst)
                if inst.sg.statemem.iswoodcutter then
                    inst.sg:RemoveStateTag("chopping")
                end
            end),

            ----------------------------------------------
            --Normal chop

            TimeEvent(2 * FRAMES, function(inst)
                if not inst.sg.statemem.iswoodcutter then
                    inst:PerformBufferedAction()
                end
            end),

            TimeEvent(9 * FRAMES, function(inst)
                if not inst.sg.statemem.iswoodcutter then
                    inst.sg:RemoveStateTag("prechop")
					inst:RemoveTag("prechop")
                end
            end),

            TimeEvent(14 * FRAMES, function(inst)
                if not inst.sg.statemem.iswoodcutter and
                    inst.components.playercontroller ~= nil and
                    inst.components.playercontroller:IsAnyOfControlsPressed(
                        CONTROL_PRIMARY,
                        CONTROL_ACTION,
                        CONTROL_CONTROLLER_ACTION) and
                    inst.sg.statemem.action ~= nil and
                    inst.sg.statemem.action:IsValid() and
                    inst.sg.statemem.action.target ~= nil and
                    inst.sg.statemem.action.target.components.workable ~= nil and
                    inst.sg.statemem.action.target.components.workable:CanBeWorked() and
                    inst.sg.statemem.action.target:IsActionValid(inst.sg.statemem.action.action) and
                    CanEntitySeeTarget(inst, inst.sg.statemem.action.target) then
					--No fast-forward when repeat initiated on server
					inst.sg.statemem.action.options.no_predict_fastforward = true
                    inst:ClearBufferedAction()
                    inst:PushBufferedAction(inst.sg.statemem.action)
                end
            end),

            TimeEvent(16 * FRAMES, function(inst)
                if not inst.sg.statemem.iswoodcutter then
                    inst.sg:RemoveStateTag("chopping")
                end
            end),
        },

        events =
        {
            EventHandler("unequip", function(inst) inst.sg:GoToState("idle") end),
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    --We don't have a chop_pst animation
                    inst.sg:GoToState("idle")
                end
            end),
        },

		onexit = function(inst)
			inst:RemoveTag("prechop")
		end,
    },    State{
        name = "mine",
        tags = { "premine", "mining", "working" },

        onenter = function(inst)
            inst.sg.statemem.action = inst:GetBufferedAction()
            inst.AnimState:PlayAnimation("pickaxe_loop")
			inst:AddTag("premine")
        end,

        timeline =
        {
            TimeEvent(7 * FRAMES, function(inst)
                if inst.sg.statemem.action ~= nil then
                    PlayMiningFX(inst, inst.sg.statemem.action.target)
                end
				inst.sg.statemem.recoilstate = "mine_recoil"
                inst:PerformBufferedAction()
            end),

            TimeEvent(9 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("premine")
				inst:RemoveTag("premine")
            end),

            TimeEvent(14 * FRAMES, function(inst)
                if inst.components.playercontroller ~= nil and
                    inst.components.playercontroller:IsAnyOfControlsPressed(
                        CONTROL_PRIMARY,
                        CONTROL_ACTION,
                        CONTROL_CONTROLLER_ACTION) and
                    inst.sg.statemem.action ~= nil and
                    inst.sg.statemem.action:IsValid() and
                    inst.sg.statemem.action.target ~= nil and
                    ((inst.sg.statemem.action.target.components.workable ~= nil and
                        inst.sg.statemem.action.target.components.workable:CanBeWorked()) or
                    (inst.sg.statemem.action.target.components.lunarhailbuildup ~= nil and
                        inst.sg.statemem.action.target.components.lunarhailbuildup:IsBuildupWorkable()
                    )) and
                    inst.sg.statemem.action.target:IsActionValid(inst.sg.statemem.action.action) and
                    CanEntitySeeTarget(inst, inst.sg.statemem.action.target) then
					--No fast-forward when repeat initiated on server
					inst.sg.statemem.action.options.no_predict_fastforward = true
                    inst:ClearBufferedAction()
                    inst:PushBufferedAction(inst.sg.statemem.action)
                end
            end),
        },

        events =
        {
            EventHandler("unequip", function(inst) inst.sg:GoToState("idle") end),
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.AnimState:PlayAnimation("pickaxe_pst")
                    inst.sg:GoToState("idle", true)
                end
            end),
        },

		onexit = function(inst)
			inst:RemoveTag("premine")
		end,
    },
}
