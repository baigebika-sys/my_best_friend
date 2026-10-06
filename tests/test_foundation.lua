-- Exercises the real work/core/crafting/resource modules, with vanilla
-- BufferedAction and selected vanilla action functions. World/nav/builder mocked.
package.path='my_best_friend/scripts/?.lua;'..package.path
function Class(ctor)
    local c={};c.__index=c
    return setmetatable(c,{__call=function(_,...) local o=setmetatable({},c);ctor(o,...);return o end})
end
local now=0
GetTime=function()return now end
Vector3=function(x,y,z)return {x=x,y=y,z=z}end
DynamicPosition=function(p)return {GetPosition=function()return p end}end
RoundBiasedUp=function(n)return math.floor(n+.5)end
TUNING={STACK_SIZE_SMALLITEM=40}
EQUIPSLOTS={HANDS='hands',BODY='body'}
STRINGS={NAMES={TWIGS='树枝',FLINT='燧石',ROCKS='石头',AXE='斧头',PICKAXE='鹤嘴锄',CUTSTONE='石砖'}}
ACTIONS={};for _,id in ipairs({'CHOP','MINE','PICK','PICKUP','BUILD','GIVETOPLAYER','YBF_GROUND_PICKUP','YBF_CRAFT','YBF_GIVE','YBF_EQUIP','YBF_TECH','REMOVELUNARBUILDUP','TERRAFORM','TERRAFORM_REMOVE'})do ACTIONS[id]={id=id,distance=2}end
TOOLACTIONS={CHOP=true,MINE=true}
ShouldItemMimicBeRevealedFor=function()return false end
ShouldBlockGiving=function()return false end
TheWorld={ismastersim=true}
dofile('tests/reference/bufferedaction.lua')
dofile('tests/reference/actions_work.lua')
local Tool=dofile('tests/reference/tool.lua')
local Uses=dofile('tests/reference/finiteuses.lua')
local Inventory=require('ybf_work_inventory')
local Resources=require('ybf_work_resources')
local Crafting=require('ybf_work_crafting')
local Work=require('components/ybf_work')
LootTables={gold={{'rocks',1},{'flint',1},{'goldnugget',1}},plain={{'rocks',1},{'flint',1}}}
AllRecipes={}
local function recipe(name,ingredients,level,output)
    local costs={};for prefab,n in pairs(ingredients)do costs[#costs+1]={type=prefab,amount=n}end
    AllRecipes[name]={name=name,product=name,ingredients=costs,level={SCIENCE=level or 0},numtogive=output or 1}
end
recipe('axe',{twigs=1,flint=1});recipe('pickaxe',{twigs=2,flint=2});recipe('cutstone',{rocks=3},1)
GetValidRecipe=function(n)return AllRecipes[n]end
CanPrototypeRecipe=function(level,tech)return (level.SCIENCE or 0)<=(tech.SCIENCE or 0)end
local scans,world,notices,friend,owner,w,action,sgtags,buildcalls,sham
local guid=0
local function entity(prefab,x,z)
    guid=guid+1
    local e={GUID=guid,prefab=prefab,components={},replica={},valid=true,x=x or 0,z=z or 0,tags={}}
    e.Transform={GetWorldPosition=function()return e.x,0,e.z end}
    function e:IsValid()return self.valid end
    function e:IsInLimbo()return self.limbo or false end
    function e:HasTag(t)return self.tags[t]==true end
    function e:AddTag(t)self.tags[t]=true end
    function e:RemoveTag(t)self.tags[t]=nil end
    function e:GetDisplayName()return self.prefab end
    function e:GetPosition()return Vector3(self.x,0,self.z)end
    function e:GetDistanceSqToInst(t)return (self.x-t.x)^2+(self.z-t.z)^2 end
    function e:DoPeriodicTask()return {Cancel=function()end}end
    function e:PushEvent()end
    function e:ListenForEvent()end
    function e:RemoveEventCallback()end
    function e:Remove()self.valid=false end
    function e:OnUsedAsItem(a)if self.components.finiteuses then self.components.finiteuses:OnUsedAsItem(a)end end
    return e
end
local function item(prefab,n)
    local e=entity(prefab);e.n=n or 1
    e.components.inventoryitem={owner=nil,canbepickedup=true,cangoincontainer=true}
    e.replica.inventoryitem={IsHeldBy=function(_,inst)return e.components.inventoryitem.owner==inst end}
    if prefab~='axe' and prefab~='pickaxe' then
        e.components.stackable={StackSize=function()return e.n end,RoomLeft=function()return 40-e.n end}
    else
        e.components.equippable={equipslot='hands',IsRestricted=function()return false end,ShouldPreventUnequipping=function()return false end}
        e.components.tool=Tool(e);e.components.tool:SetAction(prefab=='axe' and ACTIONS.CHOP or ACTIONS.MINE,1)
        e.components.finiteuses=Uses(e);e.components.finiteuses:SetConsumption(prefab=='axe' and ACTIONS.CHOP or ACTIONS.MINE,1)
        e.components.finiteuses.onfinished=function()e:Remove()end
    end
    return e
end
local function inventory(inst)
    local inv={inst=inst,itemslots={},equipslots={},maxslots=16,acceptsstacks=true,isopen=true,capacity=999}
    inst.components.inventory=inv
    function inv:GetOverflowContainer()return self.overflow end
    function inv:GetEquippedItem(slot)return self.equipslots[slot]end
    function inv:IsOpenedBy()return self.isopen end
    function inv:CanAcceptCount(e,n)return math.min(n or Inventory.Size(e),self.capacity)end
    function inv:GiveItem(e)
        for _,v in pairs(self.itemslots)do
            if v:IsValid() and v.prefab==e.prefab and v.components.stackable then v.n=v.n+e.n;e:Remove();return true end
        end
        for slot=1,self.maxslots do
            if not self.itemslots[slot] or not self.itemslots[slot]:IsValid() then self.itemslots[slot]=e;e.components.inventoryitem.owner=inst;return true end
        end
        error('mock detects unexpected ground drop')
    end
    function inv:Equip(e)
        local slot
        for k,v in pairs(self.itemslots)do if v==e then slot=k;self.itemslots[k]=nil end end
        local old=self.equipslots.hands
        if old and old:IsValid()then self.itemslots[slot or 16]=old end
        self.equipslots.hands=e;e.components.inventoryitem.owner=inst
    end
    return inv
end
local function put(inst,prefab,n)
    local e=item(prefab,n);inst.components.inventory:GiveItem(e);return e
end
local function take(inst,prefab,n)
    for _,e in ipairs(Inventory.Items(inst,false))do
        if e.prefab==prefab then
            local used=math.min(e.n,n);e.n=e.n-used;n=n-used
            if e.n==0 then
                e.valid=false
                for k,v in pairs(inst.components.inventory.itemslots)do if v==e then inst.components.inventory.itemslots[k]=nil end end
            end
            if n==0 then return end
        end
    end
    error('not enough real mock material')
end
local function reset()
    now=0;world={};notices={};action=nil;sgtags={};scans={};buildcalls=0;sham=false
    friend=entity('wilson');owner=entity('wilson',3,0)
    inventory(friend);inventory(owner)
    owner.components.trader={deleteitemonaccept=false,AbleToAccept=function()return true end,WantsToAccept=function()return true end,
        AcceptGift=function(_,giver,e,n)take(giver,e.prefab,n);put(owner,e.prefab,n);return true end}
    owner.components.health={IsDead=function()return false end}
    friend.components.health={IsDead=function()return false end}
    friend.components.ybf_friend={active=true,mode='follow',name='测试朋友',ApplyMovementPolicy=function()end,
        SetMode=function(c,m)c.mode=m;return true end,
        flower={IsValid=function()return true end,components={inventoryitem={GetGrandOwner=function()return owner end}}}}
    friend.sg={HasStateTag=function(_,t)return sgtags[t] or false end,GoToState=function()sgtags={}end}
    function friend:YBFAnnounce(text)notices[#notices+1]=text end
    function friend:GetBufferedAction()return action end
    function friend:PushBufferedAction(a)assert(action==nil);action=a end
    function friend:ClearBufferedAction()action=nil end
    function friend:DoPeriodicTask()return {Cancel=function()end}end
    friend.components.locomotor={Stop=function()end,PushAction=function(_,a)assert(action==nil,'overlapping actions');action=a end,
        GoToPoint=function(_,p)friend.x=p.x;friend.z=p.z end}
    local b={freebuildmode=false,ingredientmod=1,known={},accessible_tech_trees={SCIENCE=0},accessible_tech_trees_no_temp={SCIENCE=0}}
    friend.components.builder=b
    function b:IsBuildBuffered()return false end
    function b:EvaluateTechTrees()end
    function b:KnowsRecipe(r)return r.level.SCIENCE==0 or self.known[r.name]end
    function b:CanLearn()return true end
    function b:HasIngredients(r)
        for _,ing in ipairs(r.ingredients)do if Inventory.Count(friend,ing.type)<math.max(1,RoundBiasedUp(ing.amount*self.ingredientmod))then return false end end
        return true
    end
    function b:GetIngredients(name)
        local out={}
        for _,ing in ipairs(AllRecipes[name].ingredients)do
            local entries={};local left=math.max(1,RoundBiasedUp(ing.amount*self.ingredientmod))
            for _,e in ipairs(Inventory.Items(friend,false))do
                if e.prefab==ing.type then local used=math.min(left,e.n);entries[e]=used;left=left-used;if left==0 then break end end
            end
            out[ing.type]=entries
        end
        return out
    end
    function b:DoBuild(name)
        buildcalls=buildcalls+1
        if sham then return true end
        local r=AllRecipes[name];assert(self:HasIngredients(r))
        for p,entries in pairs(self:GetIngredients(name))do for _,n in pairs(entries)do take(friend,p,n)end end
        put(friend,r.product,r.numtogive)
        return true
    end
    function b:ConsumeTempTechBonuses()end
    function b:ActivateCurrentResearchMachine()end
    function b:UnlockRecipe(n)self.known[n]=true end
    function b:AddRecipe(n)self.known[n]=true end
    TheSim={FindEntities=function(_,x,y,z,r)
        scans[#scans+1]={x=x,z=z,r=r};local out={}
        for _,e in ipairs(world)do if e:IsValid() and (x-e.x)^2+(z-e.z)^2<=r*r then out[#out+1]=e end end
        return out
    end}
    w=Work(friend);friend.components.ybf_work=w
end
ACTIONS.YBF_GROUND_PICKUP.fn=function(a)return a.doer.components.ybf_work:PerformPickup(a)end
ACTIONS.YBF_CRAFT.fn=function(a)return a.doer.components.ybf_work:PerformCraft(a)end
ACTIONS.YBF_GIVE.fn=function(a)return a.doer.components.ybf_work:PerformGive(a)end
ACTIONS.YBF_EQUIP.fn=function(a)return a.doer.components.ybf_work:PerformEquip(a)end
ACTIONS.YBF_TECH.fn=function(a)return a.doer.components.ybf_work:PerformTech(a)end
ACTIONS.PICKUP.fn=function(a)
    if sham then return true end
    a.doer.components.inventory:GiveItem(a.target);return true
end
local function drop(prefab,n,x)
    local e=item(prefab,n);e.x=x or 2;world[#world+1]=e;return e
end
local function plant(prefab,product,x)
    local e=entity(prefab,x or 2);local c={product=product,ready=true,numtoharvest=1}
    e.components.pickable=c
    function c:CanBePicked()return self.ready end
    function c:IsStuck()return false end
    function c:Pick(picker)
        self.ready=false
        if not sham then put(picker,self.product,1) end
    end
    world[#world+1]=e;return e
end
local function source(kind,gold,x,left)
    local e=entity(kind=='chop' and 'evergreen' or gold and 'rock2' or 'rock1',x or 4)
    if kind=='chop'then e.tags.tree=true end
    e.components.lootdropper={chanceloottable=gold and 'gold' or 'plain'}
    local c={left=left or 3,action=kind=='chop' and ACTIONS.CHOP or ACTIONS.MINE}
    e.components.workable=c
    function c:CanBeWorked()return self.left>0 end
    function c:GetWorkAction()return self.action end
    function c:GetWorkLeft()return self.left end
    function c:ShouldRecoil(_,_,n)return false,n end
    function c:WorkedBy_Internal(_,n)
        if sham then return end
        self.left=self.left-n
        if self.left<=0 then
            if kind=='chop'then drop('log',3,e.x);e.tags.stump=true;c.action={}else drop('rocks',3,e.x);drop('flint',1,e.x);if gold then drop('goldnugget',1,e.x)end;e.valid=false end
        end
    end
    world[#world+1]=e;return e
end
local function tick(dt)now=now+(dt or .3);w:Tick()end
local function perform()
    local a=assert(action,'expected queued action');friend.x=a.target.x;friend.z=a.target.z
    local ok=a:Do();action=nil;return ok,a
end
local function run(limit)
    for i=1,limit or 60 do
        tick()
        if action then perform()end
        if not w:IsBusy()then return end
    end
    error('work did not finish in bounded mock ticks')
end
reset();put(friend,'twigs',3);plant('sapling','twigs');plant('sapling','twigs',4);plant('sapling','twigs',5)
assert(w:Request('collect','twigs',5));run();assert(Inventory.Count(friend,'twigs')==5)
local ready=0;for _,e in ipairs(world)do if e.components.pickable.ready then ready=ready+1 end end;assert(ready==1)
assert(w.last_result.count==5);print('PASS existing stock counts, only two needed plants harvested, confirmed owned total')
reset();put(friend,'cutgrass',4);assert(w:Request('collect','cutgrass',3));run();assert(not action and #scans==0)
reset();plant('grass','cutgrass');plant('grass','cutgrass',3);assert(w:Request('collect','cutgrass',2));run();assert(Inventory.Count(friend,'cutgrass')==2)
reset();local outside=plant('sapling','twigs',32.01);plant('sapling','twigs',32);assert(w:Request('collect','twigs',2));run();assert(Inventory.Count(friend,'twigs')==1 and outside.components.pickable.ready)
for _,s in ipairs(scans)do assert(s.r==32)end
assert(w.last_result.count==1 and w.last_result.reason:find('找不到'))
reset();friend.x=5;local origin=w:Position();plant('sapling','twigs',17.01);assert(#Resources.Scan(friend,origin,12,'twigs','collect')==0)
print('PASS grass; default radius 32 and fixed origin do not expand with movement, no owner-centered scan')
reset();local tree=source('chop',false,4,2);local axe=put(friend,'axe');assert(w:Request('collect','log',3));tick();assert(action.invobject==axe and action.action==ACTIONS.CHOP);perform()
assert(tree.components.workable.left==1 and Inventory.Count(friend,'log')==0 and axe.components.finiteuses:GetUses()==99)
sgtags.working=true;tick();assert(not action);sgtags={};run();assert(Inventory.Count(friend,'log')==3 and axe.components.finiteuses:GetUses()==98)
print('PASS vanilla CHOP + BufferedAction deduct durability; finish animation, fell tree, then actual log pickup')
reset();source('mine',false,4,2);put(friend,'pickaxe');assert(w:Request('collect','rocks',3));run();assert(Inventory.Count(friend,'rocks')==3 and Inventory.Count(friend,'flint')==0)
reset();local plain=source('mine',false,3,1);local gold=source('mine',true,5,1);put(friend,'pickaxe');assert(w:Request('collect','goldnugget',1));run();assert(plain.components.workable.left==1 and Inventory.Count(friend,'goldnugget')==1 and Inventory.Count(friend,'rocks')==0)
reset();source('mine',false,3,1);put(friend,'pickaxe');assert(w:Request('collect','goldnugget',1));run();assert(Inventory.Count(friend,'goldnugget')==0)
reset();source('mine',false,3,1);put(friend,'pickaxe');assert(w:Request('collect','flint',1));run();assert(Inventory.Count(friend,'flint')==1)
print('PASS rocks/flint/gold: real drops required, only matching drops counted/taken, gold never uses plain rock')
reset();source('chop',false,4,1);put(friend,'twigs',1);put(friend,'flint',1);assert(w:Request('collect','log',3));run()
assert(buildcalls==1 and Inventory.Count(friend,'twigs')==0 and Inventory.Count(friend,'flint')==0 and Inventory.Count(friend,'log')==3)
reset();source('chop',false,4,1);put(friend,'twigs',1);assert(w:Request('collect','log',3));run();assert(buildcalls==0 and w.last_result.reason:find('燧石'))
reset();source('mine',false,4,2);local broken=put(friend,'pickaxe');broken.components.finiteuses:SetUses(1);put(friend,'twigs',2);put(friend,'flint',2)
assert(w:Request('collect','rocks',3));run();assert(not broken:IsValid() and buildcalls==1 and Inventory.Count(friend,'rocks')==3)
reset();source('mine',false,4,2);local broken=put(friend,'pickaxe');broken.components.finiteuses:SetUses(1);assert(w:Request('collect','rocks',3));run();assert(buildcalls==0 and w.last_result.reason:find('缺少'))
print('PASS missing tools use real crafting ingredients, tool breaks/rebuilds or reports missing material; no recursive search')
reset();put(friend,'twigs',5);put(friend,'flint',5);assert(w:Request('craft','pickaxe',2));run()
assert(Inventory.Count(friend,'pickaxe',true)==2 and Inventory.Count(friend,'twigs')==1 and Inventory.Count(friend,'flint')==1 and w.last_result.count==2)
reset();put(friend,'rocks',6);assert(w:Request('craft','cutstone',2));run();assert(buildcalls==0 and Inventory.Count(friend,'rocks')==6 and w.last_result.reason:find('科技'))
friend.components.builder.accessible_tech_trees.SCIENCE=1;friend.components.builder.accessible_tech_trees_no_temp.SCIENCE=1
assert(w:Request('craft','cutstone',2));run();assert(Inventory.Count(friend,'rocks')==0 and Inventory.Count(friend,'cutstone')==2 and friend.components.builder.known.cutstone)
reset();put(friend,'rocks',3);AllRecipes.cutstone.numtogive=2;friend.components.builder.known.cutstone=true
assert(w:Request('craft','cutstone',2));run();assert(buildcalls==1 and Inventory.Count(friend,'rocks')==0 and Inventory.Count(friend,'cutstone')==2);AllRecipes.cutstone.numtogive=1
reset();put(friend,'twigs',2);put(friend,'flint',2);friend.components.builder.freebuildmode=true;assert(w:Request('craft','pickaxe',1));run();assert(buildcalls==0)
reset();put(friend,'twigs',2);put(friend,'flint',2);sham=true;assert(w:Request('craft','pickaxe',1));run();assert(buildcalls==1 and w.last_result.count==0 and Inventory.Count(friend,'flint')==2)
print('PASS actual recipe costs/output quantities, tech gate and unlock, freebuild refusal, false callback never counts craft')
reset();put(friend,'rocks',8);local keep=put(friend,'axe');put(friend,'twigs',4);assert(w:Request('give','rocks',3,owner));run()
assert(Inventory.Count(owner,'rocks')==3 and Inventory.Count(friend,'rocks')==5 and Inventory.Count(friend,'twigs')==4 and keep:IsValid())
reset();put(friend,'rocks',8);owner.components.inventory.capacity=0;assert(w:Request('give','rocks',3,owner));run();assert(Inventory.Count(friend,'rocks')==8 and Inventory.Count(owner,'rocks')==0 and w.last_result.reason:find('背包已满'))
reset();put(friend,'rocks',8);assert(w:Request('give','rocks',3,owner));tick();owner.components.inventory.capacity=0;assert(not perform());run();assert(Inventory.Count(friend,'rocks')==8)
reset();put(friend,'rocks',8);owner.components.inventory.capacity=1;assert(w:Request('give','rocks',3,owner));tick();perform();owner.components.inventory.capacity=0;run();assert(Inventory.Count(owner,'rocks')==1 and Inventory.Count(friend,'rocks')==7 and w.last_result.count==1)
print('PASS bounded stack giving exact requested count, unrelated stock/tool preserved; full at plan/execution/partial delivery retains remainder')
reset();source('chop',false,4,3);put(friend,'axe');assert(w:Request('collect','log',3));tick();local stale=action;w:Cancel(true);assert(not stale:Do() and Inventory.Count(friend,'log')==0 and friend.components.ybf_friend.mode=='follow')
reset();source('chop',false,4,3);put(friend,'axe');assert(w:Request('collect','log',3));tick();local stale=action;assert(w:Request('collect','cutgrass',1));assert(not stale:Do());plant('grass','cutgrass',2);run();assert(Inventory.Count(friend,'cutgrass')==1)
reset();local gone=plant('sapling','twigs');plant('sapling','twigs',3);assert(w:Request('collect','twigs',1));tick();gone.valid=false;run();assert(Inventory.Count(friend,'twigs')==1)
reset();plant('sapling','twigs');assert(w:Request('collect','twigs',1));tick();tick(9);tick(9);tick();assert(not w.core.job and w.last_result.reason:find('多次失败'))
reset();source('mine',false,4,3);put(friend,'pickaxe');assert(w:Request('collect','rocks',3));sham=true;run();assert(Inventory.Count(friend,'rocks')==0 and w.last_result.reason:find('多次失败'))
reset();drop('twigs',1);friend.components.inventory.capacity=0;assert(w:Start('twigs',1));run();assert(w.last_result.reason:find('背包空间'))
print('PASS stale action invalidation, replacing task, vanished/reselected target, bounded path and no-world-progress failures, full pack')
reset();friend.components.ybf_friend.mode='wait';friend.components.ybf_friend.wait_position={x=0,y=0,z=0};plant('sapling','twigs',4)
assert(w:Request('collect','twigs',1));run();assert(friend.components.ybf_friend.mode=='wait' and friend.x==0)
reset();friend.components.ybf_friend.mode='wait';friend.components.ybf_friend.wait_position={x=0,y=0,z=0};assert(w:Request('collect','twigs',1));run();assert(friend.components.ybf_friend.mode=='wait')
reset();plant('sapling','twigs');friend.components.ybf_needs={pending={},Tick=function()end};assert(w:Request('collect','twigs',1));tick();assert(not action and w.core.job.count==0)
friend.components.ybf_needs.pending=nil;run();assert(Inventory.Count(friend,'twigs')==1)
reset();put(friend,'twigs',2);drop('cutgrass',1);assert(w:Start({{item='twigs',quantity=1},{item='cutgrass',quantity=1}}));run();assert(Inventory.Count(friend,'twigs')==2 and Inventory.Count(friend,'cutgrass')==1)
print('PASS success/failure restore original wait, pending supply pauses work then rechecks, legacy mixed pickup uses owned totals')

-- Falling loot arrives later than the work callback; an unrelated next source
-- must not be worked until this source's actual drops have been checked.
reset();local tree=source('chop',false,4,1);local second=source('chop',false,6,1);put(friend,'axe')
local oldworked=tree.components.workable.WorkedBy_Internal
local delayed=false
function tree.components.workable:WorkedBy_Internal(_,n)
 self.left=0;self.action={};tree.tags.stump=true;delayed=true
end
assert(w:Request('collect','log',3));tick();perform();tick();tick();assert(w.core.job and not action and second.components.workable.left==1)
drop('log',3,4);run();assert(Inventory.Count(friend,'log')==3 and second.components.workable.left==1)
reset();source('chop',false,4,1);put(friend,'axe');friend.components.inventory.maxslots=0
assert(w:Request('collect','log',3));run();assert(w.last_result.reason:find('背包空间'))
reset();put(friend,'twigs',2);put(friend,'flint',2);friend.components.inventory.maxslots=2
assert(w:Request('craft','pickaxe',1));run();assert(buildcalls==0 and Inventory.Count(friend,'flint')==2)
reset();put(friend,'twigs',2);put(friend,'flint',2);local external=item('twigs',2)
local oldingredients=friend.components.builder.GetIngredients
friend.components.builder.GetIngredients=function(b,n)local costs=oldingredients(b,n);costs.twigs={[external]=2};return costs end
assert(w:Request('craft','pickaxe',1));run();assert(buildcalls==0 and w.last_result.reason:find('非朋友'))
reset();put(friend,'rocks',3);friend.components.builder.known.cutstone=true
friend.components.builder.DoBuild=function()buildcalls=buildcalls+1;put(friend,'cutstone',1);return true end
assert(w:Request('craft','cutstone',1));run();assert(buildcalls==1 and w.last_result.reason:find('未能确认') and Inventory.Count(friend,'rocks')==3)
reset();put(friend,'twigs',2);put(friend,'flint',2);assert(w:Request('craft','pickaxe',1));tick();take(friend,'flint',2);assert(not perform());run();assert(buildcalls==0 and w.last_result.reason:find('燧石'))
reset();put(friend,'twigs',2);put(friend,'flint',2);local heavy=item('boulder');heavy.tags.heavy=true;friend.components.inventory.equipslots.body=heavy
assert(w:Request('craft','pickaxe',1));run();assert(buildcalls==0 and heavy:IsValid())
print('PASS delayed falling loot, source capacity, pre/execution crafting checks, chest exclusion, output-without-consumption rejected, heavy item protected')

reset();put(friend,'rocks',8);put(owner,'rocks',6);assert(w:Request('give','rocks',3,owner));tick()
take(owner,'rocks',4);perform();run();assert(Inventory.Count(owner,'rocks')==5 and w.last_result.count==3)
reset();local tree=source('chop',false,4,1);tree.monster=true;put(friend,'axe');assert(w:Request('collect','log',3));run();assert(tree.components.workable.left==1)
print('PASS delivery audit captures execution-time inventory, tree monster excluded from non-combat collection')

reset();plant('sapling','twigs');local ok,why,id=w:Request('collect','twigs',1);assert(ok and id and w:Status(id).status=='running');run();assert(w:Status(id).status=='finished' and w:Status(id).result.reached_goal and w:Status(id+999).status=='unknown')
print('PASS reusable Request/Status/Cancel planner interface with bounded last result')

-- Continuous repeat window issues a fresh guarded BufferedAction while the
-- vanilla working animation is still active; normal periodic ticks do not.
reset();local tree=source('chop',false,4,3);local axe=put(friend,'axe')
assert(w:RequestPlan({{kind='tree',item='log',quantity=1}},owner));tick();perform()
sgtags.working=true;sgtags.chopping=true;tick();assert(not action)
w:ContinueSwing('chop');assert(action and action.action==ACTIONS.CHOP);perform()
w:ContinueSwing('chop');assert(action);perform();sgtags={};run()
assert(tree.components.workable.left==0 and w.last_result.count==1 and Inventory.Count(friend,'log')==3 and axe.components.finiteuses:GetUses()==97)
print('PASS continuous swing window, native durability, one-tree objective differs from one-log inventory')
reset();local axe=put(friend,'axe');assert(w:RequestPlan({{kind='equip',item='axe',quantity=1}},owner));run()
assert(friend.components.inventory:GetEquippedItem('hands')==axe and w.last_result.count==1)
reset();source('mine',true,4,1);put(friend,'pickaxe')
assert(w:RequestPlan({{kind='collect',item='rocks',quantity=3},{kind='collect',item='goldnugget',quantity=1},{kind='give',item='rocks',quantity=3},{kind='give',item='goldnugget',quantity=1}},owner));run()
assert(Inventory.Count(owner,'rocks')==3 and Inventory.Count(owner,'goldnugget')==1)
print('PASS explicit equip and multi-resource collection followed by exact delivery')
reset();source('mine',false,4,1);put(friend,'pickaxe')
local station=entity('researchlab',9);station.components.prototyper={trees={SCIENCE=1},CanUsePrototyper=function(_,doer)return doer:GetDistanceSqToInst(station)<=16 end};world[#world+1]=station
function friend.components.builder:EvaluateTechTrees()
 self.accessible_tech_trees.SCIENCE=friend:GetDistanceSqToInst(station)<=16 and 1 or 0
 self.accessible_tech_trees_no_temp.SCIENCE=self.accessible_tech_trees.SCIENCE
end
assert(w:RequestPlan({{kind='craft',item='cutstone',quantity=1,prepare=true},{kind='give',item='cutstone',quantity=1}},owner));run()
assert(buildcalls==1 and Inventory.Count(friend,'rocks')==0 and Inventory.Count(owner,'cutstone')==1 and friend.components.builder.known.cutstone)
reset();assert(w:RequestPlan({{kind='craft',item='cutstone',quantity=1,prepare=true},{kind='give',item='cutstone',quantity=1}},owner));run()
assert(buildcalls==0 and #notices>0 and w.last_result.reason:find('找不到'))
print('PASS bounded material gathering -> existing research station -> real craft/unlock -> delivery; missing materials reported')
reset();put(friend,'rocks',8);assert(w:Request('give','rocks',3,owner));tick()
assert(friend.x~=owner.x);perform();assert(Inventory.Count(owner,'rocks')==3);run()
reset();put(friend,'rocks',8);owner.components.inventory.capacity=0;assert(w:Request('give','rocks',3,owner));tick();assert(action);perform();run()
assert(friend.x==owner.x and Inventory.Count(friend,'rocks')==8 and #notices>0)
print('PASS one action transfers target stack count; full-player inventory is discovered only in actual nearby giving action')
reset();put(friend,'rocks',2);put(friend,'goldnugget',3)
assert(w:RequestPlan({{kind='give',item='rocks',quantity=3},{kind='give',item='goldnugget',quantity=3}},owner));run()
assert(Inventory.Count(owner,'rocks')==2 and Inventory.Count(owner,'goldnugget')==3 and notices[#notices]:find('还差1'))
assert(not w.last_plan_result.reached_goal and #w.last_plan_result.steps==2)
reset();put(friend,'rocks',3);put(friend,'goldnugget',3)
assert(w:RequestPlan({{kind='give',item='rocks',quantity=3},{kind='give',item='goldnugget',quantity=3}},owner));tick();perform();owner.components.inventory.capacity=0;run()
assert(Inventory.Count(owner,'rocks')==3 and Inventory.Count(friend,'goldnugget')==3 and w.last_result.count==0)
reset();local tree=source('chop',false,4,4);put(friend,'axe')
assert(w:RequestPlan({{kind='tree',item='log',quantity=1},{kind='give',item='log',quantity=3}},owner));tick();perform();sgtags.working=true
w:ContinueSwing('chop');local old=action;w:Cancel(true);assert(not old:Do());sgtags={};tick();assert(tree.components.workable.left==3 and Inventory.Count(owner,'log')==0)
reset();source('chop',false,4,4);put(friend,'axe');friend.components.ybf_needs={pending=nil,pause_requested=true,Tick=function()end}
assert(w:Request('collect','log',3));tick();perform();sgtags.working=true;w:ContinueSwing('chop');assert(not action)
friend.components.ybf_needs.pause_requested=false;w:ContinueSwing('chop');assert(action)
print('PASS partial stock proceeds to other gifts, receiver failure stops remaining gifts; repeat cancellation and needs pause prevent stale swing')
reset();plant('grass','cutgrass',28);assert(w:Request('collect','cutgrass',1));run();assert(Inventory.Count(friend,'cutgrass')==1)
reset();local golden=put(friend,'axe');golden.prefab='goldenaxe'
assert(w:RequestPlan({{kind='equip',item='axe',quantity=1}},owner));run();assert(friend.components.inventory:GetEquippedItem('hands')==golden)
reset();put(friend,'rocks',3);local queries=0
local accept=owner.components.inventory.CanAcceptCount
owner.components.inventory.CanAcceptCount=function(inv,...)queries=queries+1;assert(friend:GetDistanceSqToInst(owner)<=16);return accept(inv,...) end
assert(w:Request('give','rocks',3,owner));tick();assert(queries==0);perform();run();assert(queries>0 and Inventory.Count(owner,'rocks')==3)
reset();plant('grass','cutgrass');assert(w:Request('collect','cutgrass',1));local oldscan=TheSim.FindEntities
TheSim.FindEntities=function()error('simulated resource exception')end;tick();TheSim.FindEntities=oldscan
assert(not w.core.job and #notices>0 and w.last_result.reason:find('异常'))
print('PASS visible grass beyond old radius, equip available axe variant, receiver checks only at action, unexpected work error reports and releases controller')
reset();put(friend,'cutstone',1)
assert(w:RequestPlan({{kind='craft',item='cutstone',quantity=1,prepare=true,ensure=true},{kind='give',item='cutstone',quantity=1}},owner));run()
assert(buildcalls==0 and Inventory.Count(owner,'cutstone')==1)
reset();put(friend,'cutstone',1);put(friend,'rocks',3);friend.components.builder.known.cutstone=true
assert(w:RequestPlan({{kind='craft',item='cutstone',quantity=2,prepare=true,ensure=true},{kind='give',item='cutstone',quantity=2}},owner));run()
assert(buildcalls==1 and Inventory.Count(owner,'cutstone')==2 and Inventory.Count(friend,'rocks')==0)
print('PASS obtaining crafted goods counts owned finished stock, makes only missing output, then delivers specified quantity')

-- v0.12 goal dependency tests: same native action fixtures above, empty inventory.
local function laboratory()
 local station=entity('researchlab',9)
 station.components.prototyper={trees={SCIENCE=1},CanUsePrototyper=function(_,doer)return doer:GetDistanceSqToInst(station)<=16 end}
 world[#world+1]=station
 function friend.components.builder:EvaluateTechTrees()
  self.accessible_tech_trees.SCIENCE=friend:GetDistanceSqToInst(station)<=16 and 1 or 0
  self.accessible_tech_trees_no_temp.SCIENCE=self.accessible_tech_trees.SCIENCE
 end
 return station
end
local function goal(item,n,deliver)return w:RequestGoal({{item=item,quantity=n}},deliver~=false,owner)end
reset();drop('rocks',3);laboratory();assert(goal('cutstone',1));run(200)
assert(buildcalls==1 and Inventory.Count(owner,'cutstone')==1 and Inventory.Count(friend,'rocks')==0)
assert(Inventory.Count(friend,'pickaxe',true)==0 and not w.core.job and friend.components.builder.known.cutstone)
print('PASS EMPTY inventory + loose rocks + initially locked science recipe -> real-cost craft/unlock -> exact delivery (simulated world)')
reset();plant('sapling','twigs');plant('sapling','twigs',3);drop('flint',2);local ore=source('mine',false,4,3);laboratory()
assert(goal('cutstone',1));run(200)
assert(buildcalls==2 and Inventory.Count(owner,'cutstone')==1 and Inventory.Count(friend,'pickaxe',true)==1)
assert(ore.components.workable.left==0 and friend.components.inventory:GetEquippedItem('hands').components.finiteuses:GetUses()==97)
assert(Inventory.Count(friend,'twigs')==0 and Inventory.Count(friend,'flint')==0 and Inventory.Count(friend,'rocks')==0)
print('PASS EMPTY inventory -> harvest tool ingredients -> real pickaxe cost/equip/durability -> ore/drop pickup -> science/cutstone/delivery')
reset();plant('sapling','twigs');plant('sapling','twigs',3);drop('flint',1);source('mine',false,4,1);laboratory()
friend.components.ybf_friend.mode='wait';assert(goal('cutstone',1));run(200)
assert(w.core.job and w.core.job.blocked and Inventory.Count(friend,'flint')==1)
assert(not w:IsBusy() and friend.components.ybf_friend.mode=='wait' and notices[#notices]:find('燧石'))
local blockedscans=#scans;for _=1,20 do tick()end;assert(#scans==blockedscans)
drop('flint',1);assert(w:ResumeGoal());run(200);assert(Inventory.Count(owner,'cutstone')==1 and friend.components.ybf_friend.mode=='wait')
print('PASS precise missing material retains acquired stock/progress, releases movement in wait, no rescan loop, explicit resume completes')
reset();drop('rocks',3);assert(goal('cutstone',1));run(200)
assert(w.core.job.blocked.code=='missing_technology' and Inventory.Count(friend,'rocks')==3 and buildcalls==0)
laboratory();assert(w:ResumeGoal());run(200);assert(Inventory.Count(owner,'cutstone')==1)
reset();drop('rocks',3);friend.components.builder.known.cutstone=true;assert(goal('cutstone',1));run(200)
assert(buildcalls==1 and Inventory.Count(owner,'cutstone')==1)
print('PASS missing technology retains materials and resumes; unlocked recipe needs no science station')
reset();source('mine',false,4,3);plant('sapling','twigs');plant('sapling','twigs',3)
assert(goal('cutstone',1));run(200);assert(w.core.job.blocked.code=='dependency_cycle' and buildcalls==0 and notices[#notices]:find('循环依赖'))
reset();assert(goal('gears',1));run();assert(w.core.job.blocked and notices[#notices]:find('gears'))
reset();drop('cutstone',2);assert(goal('cutstone',1));run();assert(buildcalls==0 and Inventory.Count(owner,'cutstone')==1 and Inventory.Count(friend,'cutstone')==1)
print('PASS cyclic tool/flint mining dependency and unavailable material stop finitely; existing finished output skips all crafting')
reset();put(friend,'rocks',3);put(friend,'goldnugget',3)
assert(w:RequestGoal({{item='rocks',quantity=3},{item='goldnugget',quantity=3}},true,owner));tick();perform()
owner.components.inventory.capacity=0;run(200)
assert(Inventory.Count(owner,'rocks')==3 and Inventory.Count(friend,'goldnugget')==3 and w.core.job.given.rocks==3 and w.core.job.blocked)
owner.components.inventory.capacity=999;assert(w:ResumeGoal());run(200)
assert(Inventory.Count(owner,'rocks')==3 and Inventory.Count(owner,'goldnugget')==3)
reset();drop('rocks',3);laboratory();assert(goal('cutstone',1));tick();local stale=action;w:Cancel(true);assert(not stale:Do());tick();assert(buildcalls==0 and not w.core.job)
reset();drop('rocks',3);assert(goal('cutstone',1));run();assert(w:HasTask() and not w:IsBusy());w:Cancel(true);assert(not w:HasTask())
print('PASS partial multi-item gift and resume never re-gathers delivered stock; stop invalidates pending/blocked tasks')
reset();drop('rocks',6);laboratory();local savedoutput=AllRecipes.cutstone.numtogive;AllRecipes.cutstone.numtogive=2
assert(goal('cutstone',3));run(200);assert(buildcalls==2 and Inventory.Count(owner,'cutstone')==3 and Inventory.Count(friend,'cutstone')==1 and Inventory.Count(friend,'rocks')==0)
AllRecipes.cutstone.numtogive=savedoutput
print('PASS planner uses actual recipe output/batch costs, delivers only requested amount and retains excess')

-- Invoke the same server endpoint as the in-game chat RPC, not RequestPlan.
-- Provider response and JSON transport are simulated; this does NOT verify AI semantics.
local Communication=require('ybf_communication')
local ChatServer=require('ybf_chat_server')
local function chatfixture(case)
 reset();owner.userid='test-owner'
 local flower=entity('ybf_friendship_flower');flower.tags.ybf_friendship_flower=true
 flower._ybf_friend=friend;flower.components.inventoryitem={GetGrandOwner=function()return owner end}
 friend.components.ybf_friend.flower=flower
 local game=entity('world');game.state={phase='day'}
 local wires={};local serial=0;local sent=0;local packet;local replies={}
 local function encode(data)serial=serial+1;wires[tostring(serial)]=data;return tostring(serial)end
 local G={Ents={[flower.GUID]=flower},EQUIPSLOTS=EQUIPSLOTS,math=math,GetTimeReal=function()return now*1000 end,
  json={encode_compliant=encode,decode=function(raw)return wires[raw]end},
  GetClientModRPC=function()return {}end,SendModRPCToClient=function(_,_,raw)replies[#replies+1]=wires[raw]end,
  TheNet={Announce=function()end},TheSim={QueryServer=function(_,url,cb,method,body)
   if method=='POST' and url:match('/tasks$')then
    sent=sent+1;packet=wires[body]
    cb(encode({protocol=packet.protocol,request_id=packet.request_id,friend_id=packet.friend_id,task_id=packet.request_id,
     instance_id=string.rep('b',32),state='done',reply='先检查',action='goal',item={targets={{item='cutstone',quantity=1}},deliver=true}}),true,200)
   end
  end}}
 if case=='loose' then drop('rocks',3);laboratory()
 elseif case=='mine' or case=='stop' then plant('sapling','twigs');plant('sapling','twigs',3);drop('flint',2);source('mine',false,4,3);laboratory()
 else drop('rocks',3)end
 local chat=ChatServer.New(G,game,Communication)
 chat:Send(owner,'我想要一个石砖','测试朋友','chat-goal-'..case,friend.GUID)
 assert(sent==1 and packet.message=='我想要一个石砖' and packet.game_state.work.version=='0.12.1' and packet.game_state.work.radius==32)
 assert(w.core.job and w.core.job.kind=='goal' and w.core.job.deliver)
 chat:Send(owner,'我想要一个石砖','测试朋友','chat-goal-'..case,friend.GUID);assert(sent==1)
 if case=='stop' then
  tick();local stale=action;assert(stale)
  chat:Send(owner,'停止任务','测试朋友','chat-immediate-stop',friend.GUID)
  assert(not w.core.job and not stale:Do() and sent==1 and buildcalls==0);return
 end
 run(200)
 if case=='missing' then
  assert(w.core.job.blocked.code=='missing_technology' and Inventory.Count(friend,'rocks')==3)
  chat:Send(owner,'停止任务','测试朋友','chat-stop',friend.GUID);assert(not w.core.job and sent==1)
 else assert(Inventory.Count(owner,'cutstone')==1 and buildcalls==(case=='mine' and 2 or 1))end
end
chatfixture('loose');chatfixture('mine');chatfixture('missing');chatfixture('stop')
print('PASS actual chat server RPC handler -> context/snapshot -> simulated provider result -> real communication dispatch -> all THREE goal cases; duplicate chat tag ignored (NOT real model/game verification)')

reset();drop('rocks',3);laboratory();friend.components.ybf_needs={pending={},Tick=function()end}
assert(goal('cutstone',1));local deadline=w.core.job.deadline;tick();tick();assert(not action and w.core.job.deadline>deadline)
friend.components.ybf_needs.pending=nil;run(200);assert(Inventory.Count(owner,'cutstone')==1)
reset();drop('rocks',3);assert(goal('cutstone',1));w.core.job.actions=240;run();assert(w.core.job.blocked.code=='action_limit')
reset();drop('rocks',3);assert(goal('cutstone',1));run()
for _=1,3 do assert(w:ResumeGoal());run()end;assert(not w:ResumeGoal() and Inventory.Count(friend,'rocks')==3)
reset();drop('rocks',3);laboratory();assert(goal('cutstone',1));tick();local stale=action;assert(goal('rocks',1,false));assert(not stale:Do());run();assert(buildcalls==0 and Inventory.Count(friend,'rocks')>=1)
reset();local originalingredients=AllRecipes.cutstone.ingredients;AllRecipes.cutstone.ingredients={{type='gears',amount=1}}
assert(goal('cutstone',1));run();assert(w.core.job.blocked.code=='unobtainable_material' and notices[#notices]:find('gears'))
AllRecipes.cutstone.ingredients=originalingredients
print('PASS goal needs pause resumes same work; action/resume ceilings, replacement invalidation, actual unsupported recipe ingredient reports specific blocker')

-- v0.12.1 actual native SG timeline excerpts + production hook, mocked engine.
State=function(data)return data end
TimeEvent=function(time,fn)return {time=time,fn=fn}end
EventHandler=function(name,fn)return {name=name,fn=fn}end
FRAMES=1/30
CONTROL_PRIMARY=1;CONTROL_ACTION=2;CONTROL_CONTROLLER_ACTION=3
local Safety=require('ybf_work_safety')
local native=dofile('tests/reference/states_work.lua')
local sg={states={chop=native[1],mine=native[2]}}
Safety.Install(sg,{TimeEvent=TimeEvent,FRAMES=FRAMES})
local function frame(state,n)
 for _,event in ipairs(state.timeline) do if math.abs(event.time-n*FRAMES)<.0001 then event.fn(friend)end end
end
reset();source('chop',false,4,3);put(friend,'axe');assert(goal('log',3,false));tick()
friend.AnimState={PlayAnimation=function()end};friend.sg.statemem={}
friend.sg.RemoveStateTag=function(_,tag)sgtags[tag]=nil end
friend.components.playercontroller={IsAnyOfControlsPressed=function()return false end}
friend.PerformBufferedAction=function()local a=action;local ok=a:Do();if action==a then action=nil end;return ok end
sgtags.working=true;sgtags.chopping=true
sg.states.chop.onenter(friend);frame(sg.states.chop,2);assert(not action and w.core.job)
frame(sg.states.chop,9);frame(sg.states.chop,14);assert(action)
sg.states.chop.onenter(friend);frame(sg.states.chop,2);frame(sg.states.chop,9);frame(sg.states.chop,14);assert(action)
sg.states.chop.onenter(friend);frame(sg.states.chop,2);sgtags={};run(200)
assert(Inventory.Count(friend,'log')==3 and not w.core.job)
assert(w.last_report:find('收集好了') and not w.last_report:find('当前阶段') and not w.last_report:find('目标：'))
reset();source('chop',false,4,3);put(friend,'axe');assert(goal('log',3,false));tick()
local originalchop=ACTIONS.CHOP.fn;ACTIONS.CHOP.fn=function()error('injected native chop exception')end
friend.PerformBufferedAction=function()local a=action;local result=a:Do();if action==a then action=nil end;return result end
friend.sg.statemem={};friend.AnimState={PlayAnimation=function()end};sg.states.chop.onenter(friend)
assert(pcall(frame,sg.states.chop,2));ACTIONS.CHOP.fn=originalchop
assert(w.core.job.blocked and w.core.job.nonresumable and not action and Inventory.Count(friend,'log')==0)
reset();source('chop',false,4,3);put(friend,'axe');assert(goal('log',3,false));tick();perform()
friend.sg.statemem={iswoodcutter=false};friend.components.playercontroller={IsAnyOfControlsPressed=function()error('injected native controller exception')end}
assert(pcall(frame,sg.states.chop,14) and w.core.job.blocked and not action)
reset();friend.components.ybf_friend.active=false;friend.sg.statemem={iswoodcutter=false}
friend.components.playercontroller={IsAnyOfControlsPressed=function()error('human player error must remain native')end}
assert(not pcall(frame,sg.states.chop,14))
print('PASS native SG chop first hit/repeat, native action and timeline errors stay in friend task, human players retain native behavior, natural completion report')
reset();source('mine',false,4,3);put(friend,'pickaxe');assert(goal('rocks',3,false));tick()
friend.sg.statemem={action=action};PlayMiningFX=function()error('injected native mining FX exception')end
assert(pcall(frame,sg.states.mine,7) and w.core.job.blocked and not action)
reset();put(friend,'twigs',1);put(friend,'cutgrass',1)
assert(w:RequestGoal({{item='twigs',quantity=1},{item='cutgrass',quantity=1}},true,owner));run()
assert(w.last_report:find('给你了') and not w.last_report:find('目标：') and not w.last_report:find('当前阶段') and not w.last_report:find('ms'))
print('PASS mining shares asynchronous protection; mixed goal completion reports quantities without internal plan/transport text')
