local events,tasks={},{}
local clock=0
local refreshCalls,noticeCount=0,0
local failList,modelDelay=false,false
local live,targets={},{}
local created,removed=0,0
local pos={x=10,y=20,z=31}
local point={id='a',name='NPC shop',model='shop_model',finite=true,coords={x=10,y=20,z=30},heading=90}
local list={a=point}
local modelFail,createFail,targetFail=false,false,false
local loadingHook,listHook
local function clone(t) local r={} for k,v in pairs(t) do r[k]=type(v)=='table' and clone(v) or v end return r end
SeatingClient={}
json={encode=tostring}
lib={notify=function() noticeCount=noticeCount+1 end,callback={await=function()
    refreshCalls=refreshCalls+1
    if failList then error('test list temporarily unavailable') end
    local snapshot=list
    if listHook then local hook=listHook listHook=nil hook() end
    return {ok=true,shops=snapshot,manager=true,jobs={}}
end},requestModel=function(model)
    if model=='slow_model' then while modelDelay do coroutine.yield() end end
    if modelFail or model=='broken_model' then error('test model unavailable') end
    if loadingHook then local hook=loadingHook loadingHook=nil hook() end
    return 123
end}
exports={ox_target={
    addLocalEntity=function(_,ped,options)
        if targetFail then error('test target failure') end
        assert(live[ped] and #options==3)
        targets[ped]=options
    end,
    removeLocalEntity=function(_,ped)
        targets[ped]=nil
        if not live[ped] then error('test stale target entity') end
    end,
}}
function PlayerPedId() return 1 end
function GetEntityCoords(id)
    local p=id==1 and pos or live[id]
    return vec3(p.x,p.y,p.z)
end
function GetEntityHeading(id) return live[id].heading end
function SetEntityCoordsNoOffset(id,x,y,z) live[id].x,live[id].y,live[id].z=x,y,z end
function SetEntityHeading(id,heading) live[id].heading=heading end
local mt={__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},{__len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}) end}
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread(fn) tasks[#tasks+1]=coroutine.create(fn) end
function Wait() coroutine.yield() end
function GetGameTimer() return clock end
function GetCurrentResourceName() return 'test' end
function CreatePed(_,model,x,y,z,heading,networked,scriptHost)
    if createFail then return 0 end
    assert(model==123 and not networked and scriptHost,'NPC is created as a script-owned local ped')
    created=created+1 local ped=100+created
    live[ped]={x=x+0.3,y=y-0.2,z=z+0.8,heading=heading+10} -- Simulate creation/ground correction.
    return ped
end
function DoesEntityExist(ped) return live[ped]~=nil end
function IsPedDeadOrDying(ped) return live[ped].dead==true end
function DeleteEntity(ped) live[ped]=nil removed=removed+1 end
function SetEntityAsMissionEntity(ped,a,b) assert(a and b) live[ped].mission=true end
function SetEntityInvincible(ped,value) live[ped].invincible=value end
function SetEntityCanBeDamaged(ped,value) live[ped].damage=value end
function SetPedCanRagdoll(ped,value) live[ped].ragdoll=value end
function SetEntityVisible(ped,value) live[ped].visible=value end
function IsEntityVisible(ped) return live[ped].visible==true end
function FreezeEntityPosition(ped,value) live[ped].frozen=value end
function SetBlockingOfNonTemporaryEvents(ped,value) live[ped].blocked=value end
function SetModelAsNoLongerNeeded() end
local function resume(index)
    if coroutine.status(tasks[index])~='dead' then local ok,err=coroutine.resume(tasks[index]) assert(ok,err) end
end
local function frame()
    clock=clock+1000
    resume(2) resume(1)
    for index=3,#tasks do resume(index) end
end
local function sync(value) list=value events['ptech_omnite_shops:state'](value) end
function runShopLifecycleSpecs()
    frame() frame()
    local ped,npc=next(live)
    assert(npc and npc.mission and npc.invincible and npc.damage==false and npc.ragdoll==false and npc.frozen and npc.blocked,'NPC protection is applied')
    assert(targets[ped] and created==1)
    assert(npc.x==10 and npc.y==20 and npc.z==31 and npc.heading==90,'legacy floor offset is restored once after CreatePed correction')
    npc.x,npc.y,npc.z,npc.heading=12,22,28,180
    frame()
    assert(npc.x==10 and npc.y==20 and npc.z==31 and npc.heading==90,'displaced or rotated NPC returns to saved anchor')
    frame() assert(created==1,'healthy NPC is not duplicated')
    live[ped]=nil -- External cleanup removed the entity but the handle is still stored by the resource.
    frame() local replacement=next(live)
    assert(replacement and replacement~=ped and targets[replacement] and not targets[ped],'deleted NPC and its target are recreated')
    live[replacement].dead=true frame()
    assert(not live[replacement] and created==3,'dead NPC is replaced')
    pos.x=300 frame() assert(next(live)==nil,'distance cleanup remains supported')
    pos.x=10 frame() assert(created==4 and next(live),'returning recreates the NPC')
    sync({}) assert(next(live)==nil and next(targets)==nil,'shop deletion clears NPC and target')
    createFail=true sync({a=point}) frame() assert(next(live)==nil)
    createFail=false frame() assert(next(live),'CreatePed failure does not kill the update loop')
    sync({}) modelFail=true sync({a=point}) frame() assert(next(live)==nil)
    modelFail=false frame() assert(next(live),'model failure is retried')
    sync({}) targetFail=true sync({a=point}) frame() assert(next(live)==nil,'partial NPC is cleaned when target setup fails')
    targetFail=false frame() assert(next(live) and next(targets),'target failure can recover')
    sync({}) loadingHook=function() sync({}) end sync({a=point}) frame()
    assert(next(live)==nil,'shop removed during model loading stays removed')
    local changed=clone(point) changed.name='New name'
    changed.coordinateMode='origin' changed.coords.z=31
    local broken=clone(point) broken.id='broken' broken.model='broken_model'
    sync({a=changed,broken=broken}) frame()
    assert(next(live),'broken model does not prevent another shop from spawning')
    local _,modern=next(live)
    assert(modern.z==31,'new origin coordinate does not gain a legacy offset')
    frame() frame() assert(modern.z==31,'repeated checks do not accumulate height adjustments')
    local before=created
    sync({a=changed})
    listHook=function() sync({}) end
    events['QBCore:Client:OnJobUpdate']() frame()
    assert(next(live)==nil and created==before,'late list response cannot restore a removed shop')
    sync({a=point}) frame() assert(next(live))
    events['QBCore:Client:OnPlayerUnload']() frame()
    assert(next(live)==nil and next(targets)==nil,'logout cleans up shops')
    sync({a=point}) frame() assert(next(live)==nil,'late state after logout does not spawn NPCs')
    events['QBCore:Client:OnPlayerLoaded']() frame() assert(next(live),'login refresh restores shops')
    events.onResourceStop('test') assert(next(live)==nil and next(targets)==nil,'resource stop cleans up all NPCs')
    assert(removed>0)
end
function runShopSyncSpecs()
    failList=true frame() frame()
    assert(next(live)==nil and refreshCalls==1 and noticeCount==0,'initial sync failure is silent')
    failList=false
    for _=1,5 do frame() end
    assert(next(live),'missing startup state recovers without user action')
    local ped=next(live)
    live[ped].visible=false frame() assert(live[ped].visible,'hidden live NPC becomes visible again')
    local before=created
    list={a=clone(point)}
    local callsBefore=refreshCalls
    for _=1,16 do frame() end
    assert(refreshCalls>callsBefore and created==before,'periodic identical snapshots do not respawn a healthy NPC')
    pos.x=300 frame() assert(next(live)==nil)
    callsBefore=refreshCalls pos.x=10
    for _=1,4 do frame() end
    assert(next(live) and refreshCalls>callsBefore,'approach automatically requests current shop information')
    sync({})
    list={a=point} -- The initial broadcast for this shop was missed.
    for _=1,16 do frame() end
    assert(next(live),'periodic sync discovers previously unknown nearby shops')
    local slow=clone(point) slow.id='slow' slow.model='slow_model'
    modelDelay=true sync({a=point,slow=slow}) frame()
    local healthy=next(live) live[healthy]=nil
    frame() assert(next(live),'waiting for another model does not block recovery of nearby NPCs')
    list={a=clone(point),slow=clone(slow)}
    for _=1,16 do frame() end
    modelDelay=false frame()
    local count=0 for _ in pairs(live) do count=count+1 end
    assert(count==2,'equal state refresh keeps in-flight model requests valid without duplicate NPCs')
    events.onResourceStop('test')
    assert(next(live)==nil and next(targets)==nil)
end
