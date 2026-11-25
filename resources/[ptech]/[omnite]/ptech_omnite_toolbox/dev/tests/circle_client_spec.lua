local events,contexts,tasks={},{},{}
local mt={}
mt.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end
mt.__len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local pos=vec3(0,0,10)
local pressed,input,escaped,save,dialog
local isAdmin=false
local blipCount,removed=0,0
local activeBlips,hud,lastHint={},nil,nil
local floats=true
local frozen,collisionFail
local appearanceOpens,appearanceRequests=0,0
local appearanceDone,appearanceConfig,savedAppearance,failEditor
function TriggerServerEvent(name,appearance) assert(name=="illenium-appearance:server:saveAppearance") savedAppearance=appearance end
local nuiFocused=false
function IsNuiFocused() return nuiFocused end
function GetResourceState() return "started" end
function TriggerEvent(name,full) assert(name=="illenium-appearance:client:openClothingShop" and full==true) appearanceOpens=appearanceOpens+1 end
local prefix='ptech_omnite_toolbox:circle:'
local points={['1']={id='1',name='Circle',revision=1,bucket=0,enabled=true,radius=50,delay=10,message='Warning',
    center={x=0,y=0,z=10,heading=0},destination={x=0,y=0,z=10,heading=0}}}
function PlayerPedId() return 1 end
function GetEntityCoords() return pos end
local clock=1000
function GetGameTimer() return clock end
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread(fn) tasks[#tasks+1]=fn end
function Wait() coroutine.yield() end
function DisableControlAction() end
function IsDisabledControlJustPressed(_,key) return pressed==key end
function DrawMarker() end
function DrawLine() end
function AddBlipForRadius(x,y,z,radius) floats=floats and math.type(x)=='float' and math.type(y)=='float' and math.type(z)=='float' and math.type(radius)=='float' blipCount=blipCount+1 activeBlips[blipCount]={radius=radius} return blipCount end
function RemoveBlip(b) removed=removed+1 activeBlips[b]=nil end
function SetBlipColour(b,colour) activeBlips[b].colour=colour end
function SetBlipDisplay(b,display) activeBlips[b].display=display end
function SetBlipAlpha() end
function SetBlipAsShortRange() end
function DoScreenFadeIn() end
function DoScreenFadeOut() end
function IsScreenFadedOut() return true end
function FreezeEntityPosition(_,value) frozen=value end
function ClearPedTasksImmediately() end
function RequestCollisionAtCoord() if collisionFail then error('test streaming failure') end end
function HasCollisionLoadedAroundEntity() return true end
function SetEntityCoordsNoOffset(_,x,y,z) pos=vec3(x,y,z) end
function SetEntityHeading() end
function GetCurrentResourceName() return 'ptech_omnite_toolbox' end
local function clone(p)
    if type(p)~='table' then return p end
    local result={} for k,v in pairs(p) do result[k]=clone(v) end return result
end
json={encode=clone,decode=clone}
SeatingClient={canStart=function() return true end,notify=function() end,drawText=function() end,
    busy=function() return SeatingClient.circleManaging end}
lib={
    registerContext=function(c) contexts[c.id]=c end,showContext=function() end,hideContext=function() end,closeInputDialog=function() end,
    showTextUI=function(text) hud=text lastHint=text end,hideTextUI=function() hud=nil end,
    inputDialog=function(title,fields) dialog={title=title,fields=fields} local v=input input=nil return v end,
    alertDialog=function() return 'confirm' end,
    callback={await=function(name,_,...)
        local args={...}
        local action=name:sub(#prefix+1)
        if action=='appearance' then appearanceRequests=appearanceRequests+1 return {ok=true} end
        if action=='list' then return {ok=true,points=points,bucket=0,admin=isAdmin} end
        if action=='capture' then return {ok=true,point={x=1,y=2,z=3,heading=0}} end
        if action=='escape' then escaped=args return {ok=true} end
        if action=='save' then save=args[1] return {ok=true} end
    end}}
local zones,nextZone={},0
exports={['illenium-appearance']={startPlayerCustomization=function(_,done,config)
    if failEditor then error('editor unavailable') end
    appearanceOpens=appearanceOpens+1 appearanceDone=done appearanceConfig=config
end},ox_target={
    addBoxZone=function(_,zone) nextZone=nextZone+1 zones[nextZone]=zone return nextZone end,
    removeZone=function(_,id) zones[id]=nil end,
}}
local function target()
    local _,zone=next(zones)
    assert(zone and zone.options[1].canInteract(),'circle is targetable')
    zone.options[1].onSelect()
end
local worker
local function pressKey(key)
    worker=worker or coroutine.create(tasks[1])
    pressed=key
    local n=#tasks
    local ok,err=coroutine.resume(worker) assert(ok,err)
    pressed=nil
    for i=n+1,#tasks do tasks[i]() end
end
local function pressE() pressKey(38) end
local function pressG() pressKey(47) end
function runCircleSpecs()
    events[prefix..'state'](points,0)
    assert(blipCount==1 and activeBlips[1].display==4,'active circle explicitly displays map radius')
    assert(floats,'integer saved values are converted to native float arguments')
    local _,zone=next(zones)
    local floor=points['1'].center.z-1.0
    assert(zone.coords.z-zone.size.z/2<floor and zone.coords.z+zone.size.z/2>points['1'].center.z,
        'target box includes ground raycast hits and upper body height')
    assert(zone.drawSprite,'target point is visible while targeting')
    pos=vec3(51,0,10) pressE()
    assert(appearanceOpens==0,'outside radius cannot open editor')
    pressG() assert(not contexts.omnite_circle_face_codes,'G outside circle does not open code menu')
    pos=vec3(25,0,10)
    points['1'].enabled=false pressE() assert(appearanceOpens==0,'disabled circle cannot open editor') points['1'].enabled=true
    nuiFocused=true pressE() assert(appearanceOpens==0,'other NUI prevents opening') nuiFocused=false
    pressE()
    assert(not dialog and appearanceOpens==1,'E opens full character editor instead of access dialog')
    assert(lastHint:find('初期キャラ設定',1,true),'character creation prompt is shown')
    assert(appearanceConfig.headBlend and appearanceConfig.components and appearanceConfig.componentConfig.jackets
        and appearanceConfig.propConfig.hats,'direct editor receives full character options')
    pressE() assert(appearanceOpens==1,'repeated E does not open multiple editors')
    clock=clock+2500 pressE()
    assert(appearanceOpens==1,'active editor blocks reopening beyond debounce')
    appearanceDone({model='mp_f_freemode_01'})
    assert(savedAppearance and savedAppearance.model=='mp_f_freemode_01','submit saves appearance')
    pressG()
    local codes=contexts.omnite_circle_face_codes
    assert(codes and #codes.options==2,'G anywhere inside circle opens face-code menu')
    assert(codes.options[1].event=='illenium-appearance:client:generateFaceCode','code generation uses existing surgeon handler')
    assert(codes.options[2].event=='illenium-appearance:client:importFaceCode','code import uses existing surgeon handler')
    assert(appearanceOpens==1,'G does not open E character editor')
    clock=clock+2500 failEditor=true pressE()
    failEditor=false clock=clock+2500 pressE()
    assert(appearanceOpens==2,'export error releases opening lock for retry')
    local previous=savedAppearance
    appearanceDone(nil)
    assert(savedAppearance==previous,'cancel does not save appearance')
    pos=vec3(0,0,10) input={'4155'} target()
    assert(dialog.title=='脱出パスワード' and dialog.fields[1].password,'ordinary target opens password dialog')
    assert(escaped[1]=='1' and escaped[2]=='4155','password submitted to server')
    assert(not SeatingClient.circleManaging and not contexts.omnite_circle_edit,'ordinary player cannot edit')
    isAdmin=true
    target()
    local edit=contexts.omnite_circle_edit
    assert(edit.options[1].title=='脱出パスワード','admin first option is escape password')
    edit.onExit()
    SeatingClient.openCircles()
    contexts.omnite_circle_list.options[1].onSelect()
    edit=contexts.omnite_circle_edit
    assert(edit.options[1].title=='サークルの設定','new circle has settings')
    assert(activeBlips[blipCount].colour==5 and activeBlips[blipCount].radius==50,'unsaved circle has yellow map preview')
    input={'New circle',75,'Return in {seconds}',5,true}
    edit.options[1].onSelect()
    assert(activeBlips[blipCount].radius==75,'range changes refresh map preview')
    contexts.omnite_circle_edit.options[5].onSelect()
    assert(save.radius==75 and save.delay==5 and save.enabled and save.center.x==1,'settings saved')
    assert(not SeatingClient.circleManaging,'saving releases busy state')
    points['1'].enabled=false
    events[prefix..'state'](points,0)
    assert(next(activeBlips)==nil,'disabled circle is hidden and saved draft preview is cleaned up')
    input={'4155'} target()
    assert(contexts.omnite_circle_edit.options[1].title=='脱出パスワード','disabled point remains accessible')
    events[prefix..'travel']({x=100,y=200,z=30,heading=0})
    assert(pos.x==100 and not frozen and not SeatingClient.teleporting,'server-authorized travel restores movement')
    collisionFail=true
    events[prefix..'travel']({x=200,y=300,z=30,heading=0})
    assert(not frozen and not SeatingClient.teleporting,'streaming error releases freeze and busy state')
    events.onResourceStop('ptech_omnite_toolbox')
    assert(not SeatingClient.circleManaging,'resource stop releases menu state')
    assert(next(zones)==nil,'resource stop removes target zones')
end
