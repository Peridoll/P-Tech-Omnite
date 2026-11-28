local events,contexts,tasks={},{},{}
local mt={}
mt.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end
mt.__len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local pos=vec3(1,2,3)
local heading,pressed,now=90,{},1000
local input,save,used,cancelled
local frozen=false
local collision=true
local points={}
local prefix='ptech_omnite_toolbox:teleport:'
function PlayerPedId() return 1 end
function GetEntityCoords() return pos end
function GetEntityHeading() return heading end
function GetGameTimer() now=now+500 return now end
function IsPedDeadOrDying() return false end
function IsPedInAnyVehicle() return false end
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread(fn) tasks[#tasks+1]=fn end
function Wait() coroutine.yield() end
function DisableControlAction() end
function IsDisabledControlJustPressed(_,key) return pressed[key] end
function DrawMarker() end
function TriggerServerEvent(_,token) cancelled=token end
function DoScreenFadeOut() end
function IsScreenFadedOut() return true end
function DoScreenFadeIn() end
function RequestCollisionAtCoord() end
function HasCollisionLoadedAroundEntity() return collision end
function FreezeEntityPosition(_,value) frozen=value end
function SetEntityCoordsNoOffset(_,x,y,z) pos=vec3(x,y,z) end
function SetEntityHeading(_,value) heading=value end
function GetCurrentResourceName() return 'ptech_omnite_toolbox' end
SeatingClient={canStart=function() return true end,notify=function() end,drawText=function() end,
    busy=function() return SeatingClient.teleportManaging or SeatingClient.teleporting end}
lib={showTextUI=function() end,hideTextUI=function() end,
    registerContext=function(context) contexts[context.id]=context end,showContext=function() end,
    inputDialog=function() local v=input input=nil return v end,
    alertDialog=function() return 'confirm' end,
    callback={await=function(name,_,...)
        local args={...}
        if name=='ptech_omnite_seating:tool' then return {ok=true,admin=true} end
        local action=name:sub(#prefix+1)
        if action=='list' then return {ok=true,points=points,bucket=0} end
        if action=='begin' then return {ok=true,token=55,name='',mode='both'} end
        if action=='capture' then return {ok=true,point={x=pos.x,y=pos.y,z=pos.z,heading=heading}} end
        if action=='save' then save=args return {ok=true,id='1'} end
        if action=='use' then
            used=args
            local p=points[args[1]]
            return {ok=true,destination=p[args[2]=='a' and 'b' or 'a']}
        end
    end}}
local workers={}
local function step(index)
    workers[index]=workers[index] or coroutine.create(tasks[index])
    local ok,err=coroutine.resume(workers[index]) assert(ok,err)
end
local function press(key)
    pressed[key]=true step(2) pressed={}
end
local function state(value)
    points=value events[prefix..'state'](value,0)
end
function runTeleportSpecs()
    SeatingClient.openTeleporters()
    assert(SeatingClient.teleportManaging and contexts.omnite_teleport_list)
    contexts.omnite_teleport_list.options[1].onSelect()
    assert(contexts.omnite_teleport_draft.options[5].disabled,'cannot save until both points and name selected')
    input={'屋上'} contexts.omnite_teleport_draft.options[1].onSelect()
    input={'a_to_b'} contexts.omnite_teleport_draft.options[2].onSelect()
    contexts.omnite_teleport_draft.options[3].onSelect()
    press(38)
    pos=vec3(100,200,30) heading=180
    contexts.omnite_teleport_draft.options[4].onSelect()
    press(38)
    assert(not contexts.omnite_teleport_draft.options[5].disabled,'capture enables save')
    contexts.omnite_teleport_draft.options[5].onSelect()
    assert(save[1]==55 and save[2]=='屋上' and save[3]=='a_to_b' and not SeatingClient.teleportManaging,'draft submits selected mode and exits management')
    local p={id='1',name='屋上',mode='both',revision=1,bucket=0,a={x=1,y=2,z=3,heading=90},b={x=100,y=200,z=30,heading=180}}
    state({['1']=p}) pos=vec3(1,2,3)
    step(1) press(38)
    assert(used[1]=='1' and used[2]=='a' and used[3]==1,'E selects nearby entrance')
    assert(pos.x==100 and pos.y==200 and heading==180 and not frozen and not SeatingClient.teleporting,'travel restores movement and heading')
    step(1) press(38)
    assert(used[2]=='b' and pos.x==1,'bidirectional return selects B entrance')
    local second={id='2',name='別の屋上',mode='a_to_b',revision=1,bucket=0,a=p.a,b=p.b}
    state({['1']=p,['2']=second})
    step(1) press(38)
    assert(#contexts.omnite_teleport_access.options==2,'overlapping teleporters show selection menu')
    state({})
    contexts.omnite_teleport_access.options[1].onSelect()
    assert(not SeatingClient.teleporting,'stale deleted menu cannot travel')
    state({['1']=p}) pos=vec3(1,2,3) collision=false
    step(1) press(38)
    for i=1,20 do if not SeatingClient.teleporting then break end step(2) end
    assert(not frozen and not SeatingClient.teleporting and pos.x==1,'collision timeout restores origin and movement')
    step(1) press(38)
    assert(frozen,'travel freezes only while loading')
    events.onResourceStop('ptech_omnite_toolbox')
    assert(not frozen and not SeatingClient.teleporting and pos.x==1,'resource stop restores origin and releases movement')
    collision=true
    step(2)
    SeatingClient.openTeleporters()
    contexts.omnite_teleport_list.onExit()
    assert(not SeatingClient.teleportManaging,'closing manager releases busy state')
end
