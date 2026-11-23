local menus,exported={},{}
local copy,authorized,version=nil,true,'v3.2.10.1'
local garageCalls=0
Config={toolItem='pomnite_toolbox',garageResource='jg-advancedgarages',maxSpawnPoints=32}
exports=setmetatable({}, {__call=function(_,name,fn) exported[name]=fn end})
lib={
    notify=function() end,showTextUI=function() end,hideTextUI=function() end,
    registerContext=function(data) menus[data.id]=data end,showContext=function() end,
    setClipboard=function(text) copy=text end,
    callback={await=function(name)
        if name=='ptech_omnite_garages:authorize' then return authorized end
        garageCalls=garageCalls+1
        return {['病院ガレージ']={garageType='job',coords={x=1,y=2,z=3},spawn={{x=4,y=5,z=6,w=90},{x=7,y=8,z=9,w=180}}}}
    end},
}
function GetResourceMetadata() return version end
function AddEventHandler() end
function PlayerPedId() return 1 end
function GetVehiclePedIsIn() return 2 end
function GetEntityCoords() return {x=10,y=11,z=12} end
function GetEntityHeading() return 210 end
function IsPedDeadOrDying() return false end
function DisableControlAction() end
function IsDisabledControlJustPressed(_,key) return key==38 end
function Wait() end
function runGarageSpecs()
    exported.openManager()
    menus.omnite_garage_locations.options[1].onSelect()
    menus.omnite_garage_draft.options[3].onSelect()
    menus.omnite_garage_draft.options[5].onSelect()
    assert(copy:find('Config.JobGarageLocations',1,true),'correct JG garage category exported')
    assert(copy:find('4.0000, 5.0000, 6.0000, 90.00',1,true),'existing spawn preserved')
    assert(copy:find('10.0000, 11.0000, 12.0000, 210.00',1,true),'captured vehicle position and heading appended')
    assert(load(copy),'quoted garage name exports valid Lua')
    local before=garageCalls
    authorized=false exported.openManager()
    assert(garageCalls==before,'missing tool denies garage lookup')
    authorized=true version='v4.0.0' exported.openManager()
    assert(garageCalls==before,'JG v4 cannot accidentally use v3 flow')
end
