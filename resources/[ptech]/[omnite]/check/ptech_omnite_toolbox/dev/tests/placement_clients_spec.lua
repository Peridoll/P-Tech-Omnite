events,handlers,threads,contexts,exported={},{},{},{},{}
local zones,objects={},{}
local nextEntity=0
local position=vec3(1,2,3)
local created,deleted=0,0
local data={id='test',name='ATM',model='prop_atm_01',coords={x=1,y=2,z=2},heading=90,bucket=0,revision=1,
    label='Board',type='general',size={x=1,y=1,z=1},permissions={},sprite=61,colour=2,scale=0.8,shortRange=false,enabled=true}
local copied
SeatingClient={notify=function() end,copy=function(text) copied=text end}
local mapBlips={}
function AddBlipForCoord(x,y,z)
    assert(math.type(x)=='float' and math.type(y)=='float' and math.type(z)=='float')
    nextEntity=nextEntity+1 mapBlips[nextEntity]={x=x,y=y,z=z} return nextEntity
end
function RemoveBlip(id) mapBlips[id]=nil end
function SetBlipSprite(id,value) mapBlips[id].sprite=value end
function SetBlipColour(id,value) mapBlips[id].colour=value end
function SetBlipScale(id,value) mapBlips[id].scale=value end
function SetBlipAsShortRange(id,value) mapBlips[id].shortRange=value end
function SetBlipDisplay(id,value) mapBlips[id].display=value end
function BeginTextCommandSetBlipName() end
function AddTextComponentSubstringPlayerName(value) copied=value end
function EndTextCommandSetBlipName(id) mapBlips[id].name=copied end
lib={notify=function() end,callback={await=function() return {ok=true,points={test=data},boards={data}} end},
    registerContext=function(c) contexts[c.id]=c end,showContext=function() end,setClipboard=function() end}
exports=setmetatable({ox_target={
    addBoxZone=function(_,z) nextEntity=nextEntity+1 zones[nextEntity]=z return nextEntity end,
    removeZone=function(_,id) zones[id]=nil end,
}},{__call=function(_,name,fn) exported[name]=fn end})
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) handlers[name]=fn end
function CreateThread(fn) threads[#threads+1]=fn end
function PlayerPedId() return 1 end
function GetEntityCoords() return position end
function GetCurrentResourceName() return 'test' end
function joaat() return 123 end
function IsModelInCdimage() return true end
function IsModelValid() return true end
function RequestModel() end
function HasModelLoaded() return true end
function GetGameTimer() return 0 end
function SetModelAsNoLongerNeeded() end
function CreateObjectNoOffset() nextEntity=nextEntity+1 objects[nextEntity]=true created=created+1 return nextEntity end
function DoesEntityExist(id) return objects[id]==true end
function DeleteEntity(id) objects[id]=nil deleted=deleted+1 end
function SetEntityHeading() end
function FreezeEntityPosition() end
function SetEntityAsMissionEntity() end
function Wait() coroutine.yield() end
function showBoard() end
function runATMClientSpecs()
    local thread=coroutine.create(threads[1])
    assert(coroutine.resume(thread)) assert(created==1)
    assert(coroutine.resume(thread)) assert(created==1,'nearby ATM only spawns once')
    events['ptech_omnite_toolbox:atm:state']({}) assert(deleted==1,'bucket/state changes remove stale ATM props')
    events['ptech_omnite_toolbox:atm:state']({test=data}) assert(coroutine.resume(thread)) assert(created==2)
    position=vec3(200,200,200) assert(coroutine.resume(thread)) assert(deleted==2,'distant props are removed')
    position=vec3(1,2,3) assert(coroutine.resume(thread))
    handlers.onResourceStop('test') assert(next(objects)==nil,'resource stop removes every prop')
    SeatingClient.openATMs() assert(contexts.omnite_atms.options[1].title=='現在地にATMを設置')
    local original=lib.callback.await
    lib.callback.await=function() error('test missing ATM server callback') end
    assert(pcall(SeatingClient.openATMs),'callback failures do not escape the manager')
    lib.callback.await=original
end
function runBoardClientSpecs()
    threads[1]() local initial=next(zones) assert(initial)
    events['ptech_omnite_requests:boards:state']({data}) assert(not zones[initial],'updated state replaces old target')
    events['ptech_omnite_requests:boards:state']({}) assert(next(zones)==nil,'empty bucket has no targets')
    events['ptech_omnite_requests:boards:state']({data}) assert(next(zones))
    exported.openManager() assert(#contexts.omnite_request_boards.options==3,'manager exposes create, export and existing board')
    handlers.onResourceStop('test') assert(next(zones)==nil,'resource stop cleans target zones')
end
function runMapBlipClientSpecs()
    threads[1]() local old,p=next(mapBlips)
    assert(p and p.sprite==61 and p.colour==2 and p.scale==0.8 and p.shortRange==true and p.name=='ATM' and p.display==4,'legacy blip defaults to main map only')
    data.minimap=true events['ptech_omnite_toolbox:mapblip:state']({test=data})
    local _,shown=next(mapBlips) assert(shown.display==2 and shown.shortRange==false,'checked minimap option displays on both maps at any distance')
    data.minimap=false events['ptech_omnite_toolbox:mapblip:state']({test=data})
    local _,hidden=next(mapBlips) assert(hidden.display==4 and hidden.shortRange==true,'unchecking restores main-map-only display')
    events['ptech_omnite_toolbox:mapblip:state']({}) assert(next(mapBlips)==nil,'bucket change clears old blips')
    data.enabled=false events['ptech_omnite_toolbox:mapblip:state']({test=data}) assert(next(mapBlips)==nil,'disabled blip is hidden')
    data.enabled=true events['ptech_omnite_toolbox:mapblip:state']({test=data}) assert(not mapBlips[old] and next(mapBlips),'updated state replaces rather than duplicates')
    SeatingClient.openMapBlips()
    assert(#contexts.omnite_map_blips.options==3)
    contexts.omnite_map_blips.options[2].onSelect()
    assert(copied:find('Config.MapBlips.fixed',1,true) and load(copied),'Config export is valid Lua')
    local original=lib.callback.await
    local saved
    lib.callback.await=function(name,...)
        if name=='ptech_omnite_toolbox:mapblip:save' then local args={...} saved=args[2] return {ok=true} end
        return original(name,...)
    end
    lib.inputDialog=function() return {'Custom',52,3,1.2,true,true,true} end
    contexts.omnite_map_blips.options[1].onSelect()
    assert(saved and saved.name=='Custom' and saved.sprite==52 and saved.colour==3 and saved.scale==1.2 and saved.minimap and not saved.shortRange and saved.enabled and saved.relocate,'placement form submits the minimap checkbox')
    lib.callback.await=original
    handlers['QBCore:Client:OnPlayerUnload']() assert(next(mapBlips)==nil)
    events['ptech_omnite_toolbox:mapblip:state']({test=data}) assert(next(mapBlips)==nil,'unloaded player does not draw blips')
    handlers['QBCore:Client:OnPlayerLoaded']() assert(next(mapBlips),'player load restores blips')
    handlers.onResourceStop('test') assert(next(mapBlips)==nil,'resource stop removes blips')
    events['ptech_omnite_toolbox:mapblip:state']({test=data}) assert(next(mapBlips)==nil,'late state after stop cannot redraw blips')
end
