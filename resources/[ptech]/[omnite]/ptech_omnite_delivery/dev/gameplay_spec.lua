local thread, visible, carrying, created, deleted = nil,nil,false,0,0
local vehicle, dead, ragdoll, cuffed, present = false,false,false,false,true
local progressResult, duringProgress, duringModel = true,nil,nil
local now = 100000
local entities = {[1]=true}
local currentToken = 'mission1'
os.time=function() return now end
function PlayerPedId() return 1 end
function DoesEntityExist(entity) return entities[entity] == true end
function IsEntityPlayingAnim() return carrying end
function StopAnimTask() carrying=false end
function IsPedInAnyVehicle() return vehicle end
function IsPedDeadOrDying() return dead end
function IsPedRagdoll() return ragdoll end
function IsPedCuffed() return cuffed end
function GetEntityCoords() return {x=0,y=0,z=0} end
function CreateObject()
    created=created+1
    local object=100+created entities[object]=true return object
end
function DeleteEntity(object) entities[object]=nil deleted=deleted+1 end
function SetModelAsNoLongerNeeded() end
function SetEntityCollision() end
function GetPedBoneIndex() return 28422 end
function AttachEntityToEntity() end
function TaskPlayAnim() carrying=true end
function CreateThread(fn) thread=coroutine.create(fn) end
function Wait() coroutine.yield() end
exports={ox_inventory={Search=function()
    return present and {{count=1,metadata={delivery=currentToken}}} or {}
end}}
lib={
    isTextUIOpen=function() return visible~=nil,visible end,
    showTextUI=function(text) visible=text end,
    hideTextUI=function() visible=nil end,
    requestModel=function()
        if duringModel then local fn=duringModel duringModel=nil fn() end
        return 123
    end,
    requestAnimDict=function() end,
    notify=function() end,
    progressCircle=function(options)
        assert(options.canCancel and options.disable.move and options.disable.combat)
        if duringProgress then local fn=duringProgress duringProgress=nil fn() end
        return progressResult
    end,
    progressActive=function() return true end,
    cancelProgress=function() end,
}
local function tick()
    local ok,err=coroutine.resume(thread)
    assert(ok,err)
end
local function m(picked)
    return {token='mission1',picked=picked,pickup='pickup',shop='shop',expires=now+600,reward=400000,points=600}
end
function runGameplaySpecs()
    local G=DeliveryGameplay
    local points={pickup={label='集荷先'},shop={label='店舗'}}
    tick() assert(created==0 and visible==nil)
    G.update(m(false),points) tick()
    assert(visible:find('1/2') and visible:find('10:00') and created==0,'before collection show destination and countdown')
    G.update(m(true),points) tick()
    assert(created==1 and carrying and visible:find('2/2'),'collected box is attached with carry animation')
    tick() assert(created==1,'no duplicate props')
    carrying=false tick() assert(carrying,'interrupted carry animation recovers')
    vehicle=true tick() assert(deleted==1 and not carrying,'car entry removes prop and carry animation')
    vehicle=false tick() assert(created==2 and carrying,'leaving car restores box')
    present=false tick() assert(not carrying,'removed inventory box is not carried')
    present=true currentToken='someone_else' tick() assert(not carrying,'another delivery box cannot substitute')
    currentToken='mission1' tick() assert(carrying)
    dead=true tick() assert(not carrying) dead=false
    cuffed=true tick() assert(not carrying) cuffed=false
    ragdoll=true tick() assert(not carrying) ragdoll=false tick() assert(carrying)
    progressResult=false assert(not G.handover('deliver'),'cancelled handover must not submit')
    tick() assert(carrying,'cancel preserves box for retry')
    vehicle=true assert(not G.handover('deliver'),'must get out of car') vehicle=false
    progressResult=true assert(G.handover('deliver'),'completed handover may submit')
    duringProgress=function() G.update(nil,{}) end
    assert(not G.handover('deliver'),'mission invalidation during animation prevents submission')
    tick() assert(not carrying and visible==nil)
    G.update(m(true),points)
    local before=created
    duringModel=function() G.update(nil,{}) end
    tick() assert(created==before,'stale model load cannot attach a cancelled box')
    visible='別リソースの案内'
    G.update(m(true),points) tick()
    assert(visible=='別リソースの案内','do not replace another resource guide')
    G.update(nil,{}) assert(visible=='別リソースの案内','do not hide another resource guide')
    visible=nil G.update(m(true),points) tick()
    assert(carrying and visible)
    now=now+601 tick() assert(not carrying and visible==nil,'expiry hides box and guide')
    G.update(m(true),points) tick() assert(carrying)
    G.stop() assert(not carrying and visible==nil,'resource stop removes prop, animation and owned UI')
end
