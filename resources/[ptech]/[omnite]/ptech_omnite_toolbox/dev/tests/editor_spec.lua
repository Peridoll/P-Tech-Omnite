local events,contexts,nui,commands,tasks={},{},{},{},{}
local message,focused,saved,previewCalls=nil,false,nil,0
local saveOk=false
local playerCoords
local pressed={}
local shift=false
local markerCount=0
local axisLines={}
local doctor=false
local mlos={{id='hospital',label='病院'}}
local nextInput
local lastRows
local deleted=false
local keyMappings={}
local blocked={}
local mt={}
mt.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end
mt.__len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
function RegisterNetEvent(name,fn) events[name]=fn end
function RegisterNUICallback(name,fn) nui[name]=fn end
function AddEventHandler() end
function RegisterCommand(name,fn) commands[name]=fn end
function RegisterKeyMapping(name,description,device,key) keyMappings[name]=key end
function CreateThread(fn) tasks[#tasks+1]=fn end
function PlayerPedId() return 1 end
function GetEntityCoords() return playerCoords or vec3(1,2,3) end
function GetGameTimer() return 1234 end
function IsPedDeadOrDying() return false end
function IsPedInAnyVehicle() return false end
function DisableControlAction(_,control) blocked[control]=true end
function IsDisabledControlJustPressed(_,control) return pressed[control]==true end
function IsControlPressed(_,control) return control==21 and shift end
function DrawMarker() markerCount=markerCount+1 end
function DrawLine(...) axisLines[#axisLines+1]={...} end
function Wait() coroutine.yield() end
function GetEntityHeading() return 90 end
function GetEntityModel() return 123 end
function GetModelDimensions() return vec3(-0.3,-0.3,-1),vec3(0.3,0.3,1) end
function HasAnimDictLoaded() return true end
function StartShapeTestRay() return 7 end
function GetShapeTestResult() return 2,true,vec3(1,2,0) end
function GetPedBoneCoords() return vec3(1,2,2.6) end
function ClonePed() return 999 end
function DoesEntityExist() return true end
function SetEntityAsMissionEntity() end
function SetEntityInvincible() end
function SetEntityCollision() end
function SetEntityHasGravity() end
function SetPedCanRagdoll() end
function FreezeEntityPosition() end
function SetBlockingOfNonTemporaryEvents() end
function SetEntityAlpha() end
function ClearPedTasksImmediately() end
function SetEntityCoordsNoOffset() end
function SetEntityHeading() end
function TaskStartScenarioAtPosition() previewCalls=previewCalls+1 end
function TaskPlayAnimAdvanced() previewCalls=previewCalls+1 end
function DeleteEntity() end
function SendNUIMessage(data) message=data end
function SetNuiFocus(value) focused=value end
SeatingClient={busy=function() return false end,canStart=function() return true end,notify=function() end,drawText=function() end,debug=function() return false end,bucket=0}
local exported={}
exports=setmetatable({
    ox_inventory={useItem=function(_,data,cb) cb(true) end},
    ox_target={addSphereZone=function() return 1 end,removeZone=function() end},
},{__call=function(_,name,fn) exported[name]=fn end})
lib={hideTextUI=function() end,showTextUI=function() end,requestAnimDict=function() end,
    inputDialog=function(_,rows) lastRows=rows local result=nextInput nextInput=nil return result end,
    alertDialog=function() return 'confirm' end,
    registerContext=function(data) contexts[data.id]=data end,showContext=function() end,
    callback={await=function(name,_,data)
        if name:match(':tool$') then return {ok=true,owner='me',ems=doctor,mlos=mlos} end
        if name:match(':save$') then saved=data return {ok=saveOk} end
        if name:match(':delete$') then deleted=true return {ok=true} end
        if name:match(':registerMlo$') then mlos[#mlos+1]={id='new_mlo',label=data} return {ok=true,id='new_mlo'} end
    end},
}
local workers={}
local function step(index)
    workers[index]=workers[index] or coroutine.create(tasks[index])
    local ok,err=coroutine.resume(workers[index])
    assert(ok,err)
end
local function press(control)
    pressed[control]=true step(2) pressed={}
end
local function open(kind)
    events['ptech_omnite_seating:client:placements']({['1']={id='1',revision=1,owner='me',kind=kind,group='furniture_1',
        name='seat',mlo='hospital',coords={x=1,y=2,z=3},heading=90,style='standard'}},0)
    if not SeatingClient.managing then
        exported.usePlacementTool({})
        contexts.omnite_seat_tool.options[1].onSelect()
    end
    step(1) press(38)
    contexts.omnite_seat_edit.options[1].onSelect()
    assert(message.action=='placementState' and focused,'editor panel opens with mouse focus')
    return message.session
end
local function request(action,data)
    local result
    nui[action](data,function(value) result=value end)
    return result
end
function runEditorSpecs()
    local session=open('chair')
    local values={right=1.25,forward=-0.25,height=0.4,heading=270,style=2}
    assert(not request('placementUpdate',{session=session-1,values=values}).ok,'stale editor messages rejected')
    local bad={right=0/0,forward=0,height=0,heading=0,style=1}
    assert(not request('placementUpdate',{session=session,values=bad}).ok,'NaN rejected')
    assert(request('placementSave',{session=session,values=values}).ok)
    assert(message.saving and not request('placementUpdate',{session=session,values=values}).ok,'saving locks updates')
    assert(not request('placementCancel',{session=session}).ok,'saving cannot cancel')
    tasks[#tasks]()
    assert(math.abs(saved.coords.x-0.75)<0.0001 and math.abs(saved.coords.y-0.75)<0.0001,'movement follows the new heading rather than the initial heading')
    assert(math.abs(saved.coords.z-3.4)<0.0001 and saved.heading==270 and saved.style=='upright','height heading style saved together')
    assert(message.error and not message.saving and focused,'DB failure keeps adjustment panel')
    assert(request('placementCancel',{session=session}).ok and not focused,'cancel releases NUI focus')
    session=open('chair')
    local rotated={right=0.5,forward=0,height=0,heading=90,style=1}
    request('placementUpdate',{session=session,values=rotated})
    rotated.heading=180
    request('placementUpdate',{session=session,values=rotated})
    axisLines={} step(2)
    assert(#axisLines==57,'editor draws three arrow axes and a rotation ring')
    assert(math.abs(axisLines[1][1]-1)<0.0001 and math.abs(axisLines[1][2]-2.5)<0.0001,'rotating after translation keeps the point in place')
    assert(math.abs(axisLines[1][4]-0.15)<0.0001 and math.abs(axisLines[1][5]-2.5)<0.0001,'X guide rotates with heading')
    rotated.right=1
    request('placementSave',{session=session,values=rotated}) tasks[#tasks]()
    assert(math.abs(saved.coords.x-0.5)<0.0001 and math.abs(saved.coords.y-2.5)<0.0001,'further movement follows rotated X axis')
    assert(request('placementCancel',{session=session}).ok)
    session=open('bed')
    values.style=3
    assert(request('placementUpdate',{session=session,values=values}).ok)
    commands.omnite_seatfocus()
    assert(not focused and message.values.style==3 and #message.styles==4,'bed supports all sleeping poses; camera mode releases focus')
    blocked={} step(2)
    assert(not blocked[30] and not blocked[31] and blocked[24],'ALT allows walking while attacks remain blocked')
    playerCoords=vec3(100,100,100) step(2)
    assert(SeatingClient.placing,'walking away preserves adjustment until player returns to save')
    playerCoords=nil
    commands.omnite_seatfocus()
    assert(focused,'camera mode can return to sliders')
    local groundResult
    local ground=coroutine.create(function()
        groundResult=request('placementGround',{session=session,values=values})
    end)
    while coroutine.status(ground)~='dead' do local ok,err=coroutine.resume(ground) assert(ok,err) end
    assert(groundResult.ok and message.heightMin < -2 and message.values.height==message.heightMin,'ground button sets feet-aligned height and slider minimum')
    values.height=message.values.height
    saveOk=true
    request('placementSave',{session=session,values=values}) tasks[#tasks]()
    assert(message.action=='placementClose' and not focused,'save success cleans up panel and focus')
    assert(not request('placementUpdate',{session=session,values=values}).ok,'closed editor rejects updates')
    step(1) press(38)
    contexts.omnite_seat_edit.options[4].onSelect()
    assert(#contexts.omnite_furniture_points.options==1,'related furniture points listed together')
    contexts.omnite_furniture_points.options[1].onSelect()
    contexts.omnite_seat_edit.options[3].onSelect()
    assert(contexts.omnite_seat_create.options[2].description=='病院','new point inherits furniture MLO')
    contexts.omnite_seat_create.options[5].onSelect()
    saveOk=true
    local groupSession=message.session
    request('placementSave',{session=groupSession,values={right=1,forward=0,height=0,heading=90,style=1}}) tasks[#tasks]()
    assert(saved.group=='furniture_1','new point retains furniture grouping')
    step(1) press(38)
    contexts.omnite_seat_edit.options[2].onSelect()
    assert(deleted,'marker E opens delete action')
    playerCoords=vec3(20,20,20)
    step(1) press(38)
    assert(contexts.omnite_seat_create and contexts.omnite_seat_create.options[5].disabled,'new point asks registration details after E')
    nextInput={'新しいお店'}
    contexts.omnite_seat_create.options[1].onSelect()
    assert(contexts.omnite_seat_create.options[2].description=='新しいお店','registered MLO selected and shown')
    nextInput={'hospital'}
    contexts.omnite_seat_create.options[2].onSelect()
    assert(contexts.omnite_seat_create.options[2].description=='病院','existing MLO can be selected')
    contexts.omnite_seat_create.options[4].onSelect()
    assert(#lastRows[1].options==3,'chair counter and bed available to ordinary player')
    doctor=true
    contexts.omnite_seat_create.options[2].onSelect()
    contexts.omnite_seat_create.options[4].onSelect()
    assert(#lastRows[1].options==4,'hospital bed shown only to medical player')
    contexts.omnite_seat_create.options[5].onSelect()
    assert(message.action=='placementState' and message.name:match('^seat_%d+_%d+$'),'blank seat name gets randomized name')
    assert(message.values.height==0,'new point starts at player location')
    request('placementCancel',{session=message.session})
    assert(SeatingClient.managing,'closing editor returns to management mode')
    local a={id='2',revision=1,owner='someone_else',kind='chair',group='foreign',name='A',mlo='hospital',coords={x=20,y=20,z=20},heading=0,style='standard'}
    local b={id='3',revision=1,owner='someone_else',kind='chair',group='foreign',name='B',mlo='hospital',coords={x=20.5,y=20,z=20},heading=0,style='standard'}
    events['ptech_omnite_seating:client:placements']({['2']=a,['3']=b},0)
    step(1) press(38)
    assert(#contexts.omnite_seat_access.options==2,'nearby points prompt selection instead of forcing nearest')
    contexts.omnite_seat_access.options[2].onSelect()
    assert(contexts.omnite_seat_edit.title=='B' and not contexts.omnite_seat_edit.options[2].disabled,'chosen foreign point can be edited and deleted')
    deleted=false
    contexts.omnite_seat_edit.options[2].onSelect()
    assert(deleted,'foreign point deletion opens confirmation and sends request')
    step(1) press(38)
    contexts.omnite_seat_access.options[2].onSelect()
    contexts.omnite_seat_edit.options[1].onSelect()
    assert(message.name=='B','editing opens selected point rather than nearest')
    request('placementCancel',{session=message.session})
    -- Copy a foreign-owned point with a nondefault pose and heading.
    b.heading=123 b.style='upright'
    step(1) press(38)
    contexts.omnite_seat_access.options[2].onSelect()
    contexts.omnite_seat_edit.options[5].onSelect()
    assert(message.name=='B' and message.kind=='chair' and message.mlo=='hospital','copy inherits registration settings')
    assert(message.values.heading==123 and message.values.style==2,'copy inherits heading and selected pose')
    local copySession=message.session
    request('placementSave',{session=copySession,values=message.values}) tasks[#tasks]()
    assert(saved.id==nil and saved.revision==nil and saved.group==nil,'copy creates an independent new ID instead of updating the original')
    assert(saved.coords.x==20.5 and saved.coords.y==20 and saved.coords.z==20 and saved.style=='upright','copy preserves position and pose when saved without adjustment')
    assert(b.id=='3' and b.group=='foreign' and b.owner=='someone_else','copy leaves source identity and ownership unchanged')
    local originalRandom=math.random
    math.random=function() return 7 end
    b.name='seat_000007_1234'
    a.name='seat_000007_1235'
    step(1) press(38)
    contexts.omnite_seat_access.options[2].onSelect()
    contexts.omnite_seat_edit.options[5].onSelect()
    assert(message.name=='seat_000007_1236','copy regenerates automatic name and avoids source and existing names')
    request('placementSave',{session=message.session,values=message.values}) tasks[#tasks]()
    assert(saved.id==nil and saved.revision==nil and saved.name=='seat_000007_1236','new automatic name is saved through new-ID creation')
    assert(b.name=='seat_000007_1234' and b.id=='3','automatic-name copy does not rename source')
    math.random=originalRandom
    step(1) press(38)
    local stale=contexts.omnite_seat_access.options[2].onSelect
    events['ptech_omnite_seating:client:placements']({},0)
    stale()
    assert(not SeatingClient.placing,'deleted point cannot reopen from stale selection')
    press(202)
    assert(not SeatingClient.managing,'Esc exits management mode')
    assert(markerCount>0,'management mode draws nearby markers')
    assert(keyMappings.omnite_seatfocus_alt=='LMENU','editor uses left ALT without old cached F6 mapping')
end
