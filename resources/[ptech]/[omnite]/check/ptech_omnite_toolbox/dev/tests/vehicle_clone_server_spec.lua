local callbacks,events,threads={},{},{}
local now=10000
local admin,tool,occupied,bucket,createFail,keysFail=true,true,true,0,false,false
local typeName='automobile'
local entities={[10]={model=777,bucket=0,coords={x=0,y=0,z=10},plate='ORIGINAL'}}
local created,lastVehicle,keys=0,nil,0
local nextRandom=0
math.random=function() nextRandom=nextRandom+1 return nextRandom end
function vec3(x,y,z) return {x=x,y=y,z=z} end
function GetGameTimer() return now end
function GetPlayerPed() return 1 end
function GetVehiclePedIsIn() return occupied and 10 or 0 end
function NetworkGetEntityFromNetworkId(id) return id==100 and 10 or 0 end
function DoesEntityExist(id) return entities[id]~=nil end
function GetEntityType() return 2 end
function GetEntityRoutingBucket(id) return entities[id].bucket end
function GetPlayerRoutingBucket() return bucket end
function GetEntityCoords(id) return entities[id].coords end
function GetEntityModel(id) return entities[id].model end
function GetEntityHeading() return 45 end
function GetVehicleType() return typeName end
function IsPlayerAceAllowed() return admin end
function CreateVehicleServerSetter(model,kind,x,y,z,h)
    assert(model==777 and kind==typeName and h==45)
    if createFail then return 0 end
    created=created+1 lastVehicle=20+created
    entities[lastVehicle]={model=model,bucket=-1,coords={x=x,y=y,z=z},plate=''}
    return lastVehicle
end
function SetEntityRoutingBucket(id,value) entities[id].bucket=value end
function GetAllVehicles() local result={} for id in pairs(entities) do result[#result+1]=id end return result end
function GetVehicleNumberPlateText(id) return entities[id].plate end
function SetVehicleNumberPlateText(id,plate) entities[id].plate=plate end
function NetworkGetNetworkIdFromEntity(id) return id+1000 end
function DeleteEntity(id) assert(id~=10,'original is never deleted') entities[id]=nil end
function GetResourceState() return 'started' end
function CreateThread(fn) threads[#threads+1]=fn end
function Wait() coroutine.yield() end
function AddEventHandler(name,fn) events[name]=fn end
function GetCurrentResourceName() return 'test' end
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
exports={ox_inventory={GetItemCount=function() return tool and 1 or 0 end},qbx_vehiclekeys={GiveKeys=function(_,src,id)
    assert(src==1 and entities[id]) if keysFail then error('test key failure') end keys=keys+1
end}}
SeatingServer={finite=function(n,max) return type(n)=='number' and n==n and math.abs(n)<=max end}
local function create()
    return callbacks['ptech_omnite_toolbox:vehicleclone:create'](1,100,{x=0,y=-8,z=10})
end
local function finish(token,success) return callbacks['ptech_omnite_toolbox:vehicleclone:finish'](1,token,success) end
function runVehicleCloneSpecs()
    admin=false assert(not create().ok and created==0) admin=true
    tool=false assert(not create().ok and created==0) tool=true
    occupied=false assert(not create().ok and created==0) occupied=true
    bucket=1 assert(not create().ok and created==0) bucket=0
    assert(not callbacks['ptech_omnite_toolbox:vehicleclone:create'](1,100,{x=0/0,y=0,z=10}).ok)
    assert(not callbacks['ptech_omnite_toolbox:vehicleclone:create'](1,100,{x=1000,y=0,z=10}).ok)
    typeName='train' assert(not create().ok) typeName='automobile'
    createFail=true assert(not create().ok) createFail=false now=now+6000
    local first=create() assert(first.ok and first.model==777 and first.plate~='ORIGINAL')
    local clone=lastVehicle assert(entities[clone].bucket==0 and entities[clone].coords.y==-8)
    assert(not create().ok and created==1,'overlapping request cannot create a second clone')
    assert(not finish(first.token+1,false).ok and entities[clone],'wrong token cannot remove pending clone')
    assert(not finish(first.token,false).ok and not entities[clone],'abort removes the clone')
    assert(not create().ok,'cooldown enforced') now=now+6000
    local second=create() assert(second.ok) clone=lastVehicle
    assert(finish(second.token,true).ok and entities[clone] and keys==1,'completed clone receives keys and is retained')
    assert(not finish(second.token,true).ok and keys==1,'completion cannot run twice')
    now=now+6000 local third=create() assert(third.ok) clone=lastVehicle
    keysFail=true assert(not finish(third.token,true).ok and not entities[clone],'key failure removes pending clone') keysFail=false
    now=now+6000 local fourth=create() assert(fourth.ok) clone=lastVehicle
    admin=false assert(not finish(fourth.token,true).ok and not entities[clone],'permission revoked before completion') admin=true
    now=now+6000 local fifth=create() assert(fifth.ok) clone=lastVehicle
    now=now+Config.VehicleClone.timeout+1
    local worker=coroutine.create(threads[1]) assert(coroutine.resume(worker)) assert(coroutine.resume(worker))
    assert(not entities[clone],'unacknowledged clone expires')
    now=now+6000 assert(create().ok) clone=lastVehicle
    source=1 events.playerDropped() assert(not entities[clone],'disconnect cleanup')
    assert(create().ok) clone=lastVehicle events.onResourceStop('test') assert(not entities[clone],'stop cleanup')
    assert(entities[10].plate=='ORIGINAL','original identity is preserved')
end
