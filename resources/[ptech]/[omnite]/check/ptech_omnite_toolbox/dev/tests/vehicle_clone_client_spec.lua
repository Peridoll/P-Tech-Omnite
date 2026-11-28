local now=0
local vehicle=10
local blocked,deny,applyFail,controlled=false,false,false,true
local requests,aborts,completions,applied=0,0,0,nil
local notices={}
local mods,toggles,extras={},{},{}
local kit,livery,roof,plate
local originalProps={model=777,plate='ORIGINAL',modEngine=3,modTurbo=true,color1={10,20,30},wheelColor=6,fuelLevel=40,extras={['1']=true}}
local function copy(t) local r={} for k,v in pairs(t) do r[k]=type(v)=='table' and copy(v) or v end return r end
function vec3(x,y,z) return {x=x,y=y,z=z} end
function PlayerPedId() return 1 end
function GetVehiclePedIsIn() return vehicle end
function DoesEntityExist(id) return id==10 or id==20 end
function GetEntityModel() return 777 end
function GetModelDimensions() return {x=-1,y=-2,z=-1},{x=1,y=2,z=1} end
function GetOffsetFromEntityInWorldCoords(_,x,y,z) return {x=x,y=y,z=z+10} end
function IsAnyVehicleNearPoint() return blocked end
function GetVehicleModKit(id) assert(id==10) return 2 end
function GetVehicleMod(id,index) assert(id==10) return index%3-1 end
function GetVehicleModVariation() return true end
function IsToggleModOn(_,index) return index%2==0 end
function GetVehicleLivery() return 0 end
function GetVehicleRoofLivery() return 0 end
function DoesExtraExist(_,index) return index==1 or index==2 end
function IsVehicleExtraTurnedOn(_,index) return index==1 end
function NetworkGetNetworkIdFromEntity() return 100 end
function GetGameTimer() now=now+100 return now end
function NetworkDoesEntityExistWithNetworkId() return true end
function NetworkGetEntityFromNetworkId() return 20 end
function NetworkRequestControlOfEntity() end
function NetworkHasControlOfEntity() return controlled end
function Wait() now=now+1000 end
function SetVehicleModKit(id,value) assert(id==20) kit=value end
function SetVehicleMod(id,index,value,variation) assert(id==20 and variation) mods[index]=value end
function ToggleVehicleMod(id,index,value) assert(id==20) toggles[index]=value end
function SetVehicleLivery(id,value) assert(id==20) livery=value end
function SetVehicleRoofLivery(id,value) assert(id==20) roof=value end
function SetVehicleExtra(id,index,disabled) assert(id==20) extras[index]=disabled end
function SetVehicleNumberPlateText(id,value) assert(id==20) plate=value end
function SetVehicleOnGroundProperly(id) assert(id==20) end
SeatingClient={notify=function(message) notices[#notices+1]=message end}
lib={getVehicleProperties=function(id) assert(id==10) return copy(originalProps) end,
    setVehicleProperties=function(id,props) assert(id==20) applied=props return not applyFail end,
    callback={await=function(name,_,...)
        local args={...}
        if name=='ptech_omnite_toolbox:vehicleclone:create' then
            requests=requests+1 assert(args[1]==100 and args[2].y==-6,'spawn is behind the original')
            SeatingClient.cloneVehicle() -- busy guard prevents reentry.
            if deny then return {ok=false,message='denied'} end
            return {ok=true,token=requests,netId=200,plate='OC123456',model=777}
        end
        assert(name=='ptech_omnite_toolbox:vehicleclone:finish')
        if args[2]==true then completions=completions+1 return {ok=true,plate='OC123456'} end
        aborts=aborts+1 return {ok=false}
    end}}
function runVehicleCloneSpecs()
    vehicle=0 SeatingClient.cloneVehicle() assert(requests==0) vehicle=10
    blocked=true SeatingClient.cloneVehicle() assert(requests==0) blocked=false
    deny=true SeatingClient.cloneVehicle() assert(requests==1 and completions==0) deny=false
    SeatingClient.cloneVehicle()
    assert(requests==2 and completions==1 and kit==2,'authorized clone applies source kit')
    for index=0,49 do
        if index>=17 and index<=22 then assert(toggles[index]==(index%2==0))
        else assert(mods[index]==index%3-1) end
    end
    assert(livery==0 and roof==0 and extras[1]==false and extras[2]==true,'zero liveries and extras are preserved')
    assert(applied.modEngine==3 and applied.modTurbo and applied.color1[2]==20 and applied.wheelColor==6 and applied.fuelLevel==40)
    assert(applied.plate=='OC123456' and plate=='OC123456' and originalProps.plate=='ORIGINAL','only clone plate changes')
    applyFail=true SeatingClient.cloneVehicle() assert(aborts==1 and completions==1,'property failure rolls back clone') applyFail=false
    controlled=false SeatingClient.cloneVehicle() assert(aborts==2 and completions==1,'network control failure rolls back clone') controlled=true
    SeatingClient.cloneVehicle() assert(completions==2,'busy state clears after failures')
end
