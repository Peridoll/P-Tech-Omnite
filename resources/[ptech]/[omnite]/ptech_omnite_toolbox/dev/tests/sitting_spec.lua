local events,commands,contexts={},{},{}
local sent,lastScenario,lastAnimation,taskCount={},nil,nil,0
local openContext
local immediateClears,secondaryClears,restored=0,0,nil
local notifications={}
local frozen,collision=false,true
local threads,clock={},0
local animationAt,walks=0,0
local down,ragdoll,attached=false,false,false
LocalPlayer={state={}}
function CanPedRagdoll() return true end
function SetPedCanRagdoll() end
function IsEntityAttached() return attached end
function DetachEntity() attached=false end
local function noop() end
function vec3(x,y,z) return {x=x,y=y,z=z} end
function RegisterNetEvent(name,fn) events[name]=fn end
function RegisterCommand(name,fn) commands[name]=fn end
function RegisterKeyMapping() end
function RegisterNUICallback() end
function AddEventHandler() end
function CreateThread(fn) threads[#threads+1]=fn end
function GetGameTimer() return clock end
function Wait(ms) clock=clock+ms end
function DoesEntityExist() return true end
function TaskPlayAnim() error('exit must not play a standing animation') end
function TaskGoStraightToCoord() error('exit must not start walking') end
function SetTimeout() end
function PlayerPedId() return 1 end
function PlayerId() return 0 end
function GetPlayerServerId() return 1 end
function GetEntityCoords() return vec3(0,0,0) end
function GetEntityHeading() return 35 end
function IsEntityPositionFrozen() return frozen end
function GetEntityCollisionDisabled() return not collision end
function FreezeEntityPosition(_,value) frozen=value end
function SetEntityCollision(_,value) collision=value end
function IsPedInAnyVehicle() return false end
function IsPedDeadOrDying() return down end
function IsPedRagdoll() return ragdoll end
function IsPedCuffed() return false end
function ClearPedTasks() end
function ClearPedTasksImmediately() immediateClears=immediateClears+1 end
function ClearPedSecondaryTask() secondaryClears=secondaryClears+1 end
function SetEntityCoordsNoOffset(_,x,y,z) restored={x,y,z} end
function SetEntityHeading(_,heading) assert(type(heading)=='number','exit facing restored') end
local failSearch=false
function GetEntityModel() return 1 end
function GetModelDimensions() return vec3(-0.3,-0.3,-1),vec3(0.3,0.3,1) end
function StartShapeTestRay(x,y,z,ex,ey,ez)
    if failSearch then error('test exit search failure') end
    return {floor=z~=ez,x=x,y=y}
end
function StartShapeTestCapsule() return {} end
function GetShapeTestResult(handle)
    if handle.floor then return 2,true,vec3(handle.x,handle.y,-1),vec3(0,0,1) end
    return 2,false
end
function GetAnimDuration() return 3.1 end
function TriggerServerEvent(...) sent[#sent+1]={...} end
function TaskStartScenarioAtPosition(ped,scenario) lastScenario=scenario taskCount=taskCount+1 end
function TaskPlayAnimAdvanced(ped,dict,clip,x,y,z,rx,ry,rz,blendIn,blendOut,duration,flags) lastAnimation={dict,clip,flags} taskCount=taskCount+1 end
BeginTextCommandThefeedPost=noop EndTextCommandThefeedPostTicker=noop
function AddTextComponentSubstringPlayerName(text) notifications[#notifications+1]=text end
lib={requestAnimDict=noop,
    registerContext=function(data) contexts[data.id]=data end,
    showContext=function(id) openContext=id end,
    getOpenContextMenu=function() return openContext end,
    hideContext=function() openContext=nil end,
}
setmetatable(lib,{__index=function(_,name) error('No such export '..name..' in resource ox_lib') end})
function SetNuiFocus() end
local function sit(kind,key,allowed)
    SeatingClient.requestSit({kind=kind,key=key,lockCoords=vec3(0,0,0),sitCoords=vec3(0,0,0),heading=0,styleIds=allowed})
    events['ptech_omnite_seating:client:sitResult'](true,key)
end
local function exitSeat()
    local before=clock
    commands['+ptech_omnite_stand']()
    if not SeatingClient.canStart() then
        assert(SeatingClient.busy(),'new seating is blocked during exit')
        threads[#threads]()
        assert(clock==before,'exit adds no animation or walking delay')
    end
end
function runSittingSpecs()
    sit('chair','db:1')
    assert(#notifications==0,'sitting does not show control instructions')
    commands['+ptech_omnite_cycle_sit_style']()
    local menu=contexts.omnite_seat_styles
    assert(#menu.options==9,'all selected chair styles in G menu')
    assert(menu.options[1].title=='標準' and menu.options[2].title=='背筋を伸ばす' and menu.options[3].title=='Sit Chair')
    for _,option in ipairs(menu.options) do assert(not option.title:find('Female') and not option.title:find('Armchair') and option.title~='ゆったり','excluded poses never appear') end
    local before=#sent
    menu.options[2].onSelect()
    assert(lastScenario=='PROP_HUMAN_SEAT_CHAIR_UPRIGHT' and #sent==before,'personal style changes without DB or seat lock writes')
    frozen=true collision=false
    exitSeat()
    assert(not frozen and collision,'standing restores pre-seat freeze and collision state')
    assert(immediateClears==1 and secondaryClears==1 and restored and restored[2]>0.8 and walks==0,'chair exits directly to validated nearby location')
    assert(SeatingClient.canStart(),'seat state and movement restriction condition released after standing')
    before=taskCount menu.options[3].onSelect()
    assert(taskCount==before and not openContext,'standing closes menu and rejects stale choices')
    sit('counter','db:2')
    assert(lastScenario=='PROP_HUMAN_SEAT_BAR','counter starts in its matching posture')
    commands['+ptech_omnite_cycle_sit_style']()
    menu=contexts.omnite_seat_styles
    assert(#menu.options==10 and menu.options[1].title=='カウンター座り','counter includes bar and requested chair poses')
    for _,entry in ipairs(menu.options) do assert(entry.title~='ゆったり','armchair posture excluded from counter') end
    exitSeat()
    assert(immediateClears==2 and secondaryClears==2,'counter uses same complete exit cleanup')
    sit('bed','db:3')
    assert(frozen and collision,'ordinary bed holds lying position like preview')
    commands['+ptech_omnite_cycle_sit_style']()
    assert(#contexts.omnite_seat_styles.options==4 and contexts.omnite_seat_styles.options[1].title=='仰向け' and lastAnimation,'bed displays all registered sleeping postures')
    before=#sent
    contexts.omnite_seat_styles.options[2].onSelect()
    assert(lastAnimation[1]=='timetable@tracy@sleep@' and #sent==before,'sleep pose changes without editing saved placement')
    exitSeat()
    assert(not frozen and collision,'leaving ordinary bed restores movement and collision')
    sit('patient_bed','db:4') commands['+ptech_omnite_cycle_sit_style']()
    assert(contexts.omnite_seat_styles.title=='病院ベッドの座り方')
    exitSeat()
    sit('chair','fixed:restricted',{'upright'}) commands['+ptech_omnite_cycle_sit_style']()
    assert(#contexts.omnite_seat_styles.options==1 and contexts.omnite_seat_styles.options[1].title=='背筋を伸ばす','configured seat restrictions are respected')
    lib.getOpenContextMenu=function() error('menu unavailable') end
    exitSeat()
    assert(SeatingClient.canStart(),'UI failure cannot leave seated movement restrictions active')
    assert(sent[#sent][1]=='ptech_omnite_seating:server:stand','UI failure cannot prevent server seat release')
    lib.requestAnimDict=function() error('animation unavailable') end
    sit('chair','db:fallback') exitSeat()
    assert(SeatingClient.canStart(),'animation load failure still releases movement')
    lib.requestAnimDict=noop
    sit('chair','db:forced') commands['+ptech_omnite_stand']()
    events['ptech_omnite_seating:client:releaseSeat']('db:forced')
    assert(SeatingClient.canStart(),'forced release interrupts exit safely')
    threads[#threads]()
    assert(SeatingClient.canStart(),'late animation loader cannot restart a cancelled exit')
    down=true ragdoll=true attached=true LocalPlayer.state.dead='dead'
    assert(not SeatingClient.canStart(),'ordinary seats still reject down patients')
    events['ptech_omnite_seating:client:patientBed']({coords={x=0,y=0,z=0},heading=90},'db:patient')
    assert(frozen and not attached and lastAnimation[3]==33,'down patient is detached, laid in bed and frozen with dead-safe animation')
    local before=#sent
    commands['+ptech_omnite_stand']()
    assert(#sent==before and frozen,'down patient cannot leave bed with X')
    local tasks=taskCount
    commands['+ptech_omnite_cycle_sit_style']()
    assert(taskCount==tasks,'down patient cannot change posture')
    down=false ragdoll=false LocalPlayer.state.dead=false
    commands['+ptech_omnite_stand']()
    assert(not frozen and SeatingClient.canStart(),'revived patient can leave and restore movement')
    down=true LocalPlayer.state.dead=true
    events['ptech_omnite_seating:client:patientBed']({coords={x=0,y=0,z=0},heading=90},'db:patient-stop')
    events['ptech_omnite_seating:client:releaseSeat']('db:patient-stop')
    assert(not frozen,'forced bed release also restores frozen state while down')
    down=false LocalPlayer.state.dead=false
    failSearch=true
    sit('chair','db:search_error')
    commands['+ptech_omnite_stand']() threads[#threads]()
    assert(SeatingClient.canStart(),'search exception cannot leave exit movement restrictions active')
    assert(sent[#sent][1]=='ptech_omnite_seating:server:stand','search exception still releases server seat')
end
