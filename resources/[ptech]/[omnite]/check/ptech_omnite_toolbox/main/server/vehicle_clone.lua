local prefix='ptech_omnite_toolbox:vehicleclone:'
local pending,lastRequest={},{}
local sequence=0
local function fail(message) return {ok=false,message=message} end
local function authorize(src)
    return (IsPlayerAceAllowed(src,Config.Placement.adminAce) or IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god'))
        and (exports.ox_inventory:GetItemCount(src,Config.Placement.item) or 0)>0
end
local function discard(src)
    local p=pending[src]
    pending[src]=nil
    if p and p.vehicle and DoesEntityExist(p.vehicle) then DeleteEntity(p.vehicle) end
end
local function uniquePlate()
    for _=1,32 do
        local plate=('OC%06d'):format(math.random(0,999999))
        local used=false
        for _,vehicle in ipairs(GetAllVehicles()) do
            if GetVehicleNumberPlateText(vehicle):gsub('%s','')==plate then used=true break end
        end
        if not used then return plate end
    end
    error('Unable to allocate a clone plate')
end
lib.callback.register(prefix..'create',function(src,netId,destination)
    if not authorize(src) then return fail('管理者権限と工具箱が必要です。') end
    if pending[src] then return fail('前の複製処理を待ってください。') end
    local now=GetGameTimer()
    if lastRequest[src] and now-lastRequest[src]<Config.VehicleClone.cooldown then return fail('少し待ってから複製してください。') end
    if type(netId)~='number' or netId%1~=0 or netId<=0 or type(destination)~='table' then return fail('車両を取得できません。') end
    for _,axis in ipairs({'x','y','z'}) do if not SeatingServer.finite(destination[axis],10000) then return fail('出現位置を取得できません。') end end
    local ped=GetPlayerPed(src)
    local original=NetworkGetEntityFromNetworkId(netId)
    if ped==0 or original==0 or not DoesEntityExist(original) or GetEntityType(original)~=2
        or GetVehiclePedIsIn(ped,false)~=original or GetEntityRoutingBucket(original)~=GetPlayerRoutingBucket(src) then
        return fail('複製する車に乗った状態で操作してください。')
    end
    local c=GetEntityCoords(original)
    if (c.x-destination.x)^2+(c.y-destination.y)^2+(c.z-destination.z)^2>Config.VehicleClone.maxSpawnDistance^2 then return fail('出現位置が遠すぎます。') end
    local vehicleType=GetVehicleType(original)
    local allowed={automobile=true,bike=true,boat=true,heli=true,plane=true,submarine=true,trailer=true}
    if not allowed[vehicleType] then return fail('この種類の車両は複製できません。') end
    lastRequest[src]=now
    sequence=sequence+1
    local job={token=sequence,bucket=GetPlayerRoutingBucket(src),expires=now+Config.VehicleClone.timeout}
    pending[src]=job
    local ok,result=pcall(function()
        job.vehicle=CreateVehicleServerSetter(GetEntityModel(original),vehicleType,destination.x,destination.y,destination.z,GetEntityHeading(original))
        if not job.vehicle or job.vehicle==0 or not DoesEntityExist(job.vehicle) then error('Vehicle creation failed') end
        SetEntityRoutingBucket(job.vehicle,job.bucket)
        job.plate=uniquePlate()
        SetVehicleNumberPlateText(job.vehicle,job.plate)
        local net=NetworkGetNetworkIdFromEntity(job.vehicle)
        if net==0 then error('Vehicle has no network ID') end
        return {ok=true,token=job.token,netId=net,plate=job.plate,model=GetEntityModel(original)}
    end)
    if not ok then discard(src) print('[Omnite vehicle clone] '..tostring(result)) return fail('複製車を生成できませんでした。') end
    return result
end)
lib.callback.register(prefix..'finish',function(src,token,success)
    local p=pending[src]
    if not p or p.token~=token then return fail('複製処理が見つかりません。') end
    if success~=true or not authorize(src) or GetGameTimer()>p.expires or GetPlayerRoutingBucket(src)~=p.bucket
        or not p.vehicle or not DoesEntityExist(p.vehicle) then
        discard(src) return fail('複製を中止しました。')
    end
    SetVehicleNumberPlateText(p.vehicle,p.plate)
    if GetResourceState('qbx_vehiclekeys')=='started' then
        local ok,err=pcall(function() exports.qbx_vehiclekeys:GiveKeys(src,p.vehicle,true) end)
        if not ok then discard(src) print('[Omnite vehicle clone] Keys failed: '..tostring(err)) return fail('複製車の鍵を渡せなかったため中止しました。') end
    end
    pending[src]=nil
    return {ok=true,plate=p.plate}
end)
CreateThread(function()
    while true do
        Wait(1000)
        for src,p in pairs(pending) do
            if GetGameTimer()>p.expires or GetPlayerPed(src)==0 or GetPlayerRoutingBucket(src)~=p.bucket then discard(src) end
        end
    end
end)
AddEventHandler('playerDropped',function() discard(source) lastRequest[source]=nil end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() then for src in pairs(pending) do discard(src) end end
end)
