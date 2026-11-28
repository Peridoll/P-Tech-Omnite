local C=SeatingClient
local prefix='ptech_omnite_toolbox:vehicleclone:'
local busy=false
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok then print('[Omnite vehicle clone] '..tostring(result)) return end
    return result
end
local function position(original)
    local minimum,maximum=GetModelDimensions(GetEntityModel(original))
    local width,length=maximum.x-minimum.x,maximum.y-minimum.y
    local gap=Config.VehicleClone.spacing
    for _,offset in ipairs({{x=0,y=-length-gap},{x=width+gap,y=0},{x=-width-gap,y=0},{x=0,y=length+gap}}) do
        local c=GetOffsetFromEntityInWorldCoords(original,offset.x,offset.y,0.0)
        if not IsAnyVehicleNearPoint(c.x,c.y,c.z,math.max(width/2+0.5,1.5)) then return {x=c.x,y=c.y,z=c.z} end
    end
end
function C.cloneVehicle()
    if busy then return end
    local original=GetVehiclePedIsIn(PlayerPedId(),false)
    if original==0 or not DoesEntityExist(original) then C.notify('複製する車に乗ってから操作してください。') return end
    local destination=position(original)
    if not destination then C.notify('車の周囲に出現スペースがありません。広い場所で操作してください。') return end
    busy=true
    local ticket
    local ok,err=pcall(function()
        local props=lib.getVehicleProperties(original)
        if type(props)~='table' then error('車両の設定を取得できません。') end
        -- ox_libのバージョンに依存せず、キットと全スロットを補完します。
        local kit=GetVehicleModKit(original)
        local mods={}
        for index=0,49 do
            mods[index]={value=GetVehicleMod(original,index),variation=GetVehicleModVariation(original,index)}
            if index>=17 and index<=22 then mods[index].toggle=IsToggleModOn(original,index) end
        end
        local livery,roof=GetVehicleLivery(original),GetVehicleRoofLivery(original)
        local extras={}
        for index=0,20 do if DoesExtraExist(original,index) then extras[index]=IsVehicleExtraTurnedOn(original,index) end end
        local result=call('create',NetworkGetNetworkIdFromEntity(original),destination)
        if not result or not result.ok then error(result and result.message or 'サーバーから応答がありません。') end
        ticket=result.token
        local deadline=GetGameTimer()+math.min(Config.VehicleClone.timeout-2000,10000)
        local clone
        repeat
            if NetworkDoesEntityExistWithNetworkId(result.netId) then
                clone=NetworkGetEntityFromNetworkId(result.netId)
                if clone~=0 and DoesEntityExist(clone) then
                    NetworkRequestControlOfEntity(clone)
                    if NetworkHasControlOfEntity(clone) then break end
                end
            end
            Wait(0)
        until GetGameTimer()>=deadline
        if not clone or clone==0 or not DoesEntityExist(clone) or not NetworkHasControlOfEntity(clone) then error('複製車の読み込み・制御取得に失敗しました。') end
        if GetEntityModel(clone)~=result.model then error('複製先の車種が一致しません。') end
        props.plate=result.plate
        if lib.setVehicleProperties(clone,props)==false then error('改造設定を反映できませんでした。') end
        if kit>=0 then
            SetVehicleModKit(clone,kit)
            for index=0,49 do
                local mod=mods[index]
                if mod.toggle~=nil then ToggleVehicleMod(clone,index,mod.toggle)
                else SetVehicleMod(clone,index,mod.value,mod.variation) end
            end
        end
        if livery>=0 then SetVehicleLivery(clone,livery) end
        if roof>=0 then SetVehicleRoofLivery(clone,roof) end
        for index,enabled in pairs(extras) do SetVehicleExtra(clone,index,not enabled) end
        SetVehicleNumberPlateText(clone,result.plate)
        SetVehicleOnGroundProperly(clone)
        local completed=call('finish',ticket,true)
        if not completed or not completed.ok then error(completed and completed.message or '複製完了の確認に失敗しました。') end
        ticket=nil
        C.notify('乗車中の車を複製しました。ナンバー：'..completed.plate)
    end)
    if ticket then call('finish',ticket,false) end
    busy=false
    if not ok then C.notify(tostring(err)) print('[Omnite vehicle clone] '..tostring(err)) end
end
