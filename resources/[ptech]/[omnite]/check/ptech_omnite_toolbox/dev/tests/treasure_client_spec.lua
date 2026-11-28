local events,contexts,tasks={},{},{}
local live,targets={},{}
local counter=100
local opened,save,claims=nil,nil,0
local position={x=1,y=2,z=10}
local point={id='npc1',name='Treasure',model='test_ped',revision=1,enabled=true,coords={x=1,y=2,z=10},heading=90}
local points={npc1=point}
local notices={}
local requestHook,modelFail
SeatingClient={}
json={encode=tostring,decode=function(v) return v end}
lib={notify=function(v) notices[#notices+1]=v.description end,
    registerContext=function(c) contexts[c.id]=c end,showContext=function() end,
    inputDialog=function() return {'New treasure','test_ped',true,true} end,
    alertDialog=function() return 'confirm' end,
    requestModel=function()
        if modelFail then error('test unavailable model') end
        if requestHook then local fn=requestHook requestHook=nil fn() end
        return 123
    end,
    callback={await=function(name,_,...)
        local args={...}
        if name=='ptech_omnite_toolbox:treasure:list' then return {ok=true,points=points} end
        if name=='ptech_omnite_toolbox:treasure:stash' then return {ok=true,inventory='reward_stash'} end
        if name=='ptech_omnite_toolbox:treasure:save' then save=args[1] return {ok=true} end
        if name=='ptech_omnite_toolbox:treasure:reviews' then return {ok=true,claims={}} end
        assert(name=='ptech_omnite_toolbox:treasure:claim')
        claims=claims+1
        assert(args[1]=='npc1')
        local _,options=next(targets)
        assert(not options[1].canInteract(),'local claim guard is active') options[1].onSelect()
        return claims==1 and {ok=true,message='Received'} or {ok=false,message='Already received'}
    end}}
exports={ox_target={
    addLocalEntity=function(_,ped,options) targets[ped]=options end,
    removeLocalEntity=function(_,ped) targets[ped]=nil end,
},ox_inventory={openInventory=function(_,kind,id) opened={kind=kind,id=id} end}}
local mt={__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},{__len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}) end}
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
function PlayerPedId() return 1 end
function GetEntityCoords() return vec3(position.x,position.y,position.z) end
function GetCurrentResourceName() return 'test' end
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread(fn) tasks[#tasks+1]=coroutine.create(fn) end
function Wait() coroutine.yield() end
function joaat() return 123 end
function IsModelInCdimage() return true end
function IsModelAPed() return true end
function CreatePed(_,_,x,y,z,heading,networked,scriptHost)
    assert(not networked and scriptHost)
    counter=counter+1 live[counter]={x=x,y=y,z=z,heading=heading} return counter
end
function DoesEntityExist(id) return live[id]~=nil end
function IsPedDeadOrDying(id) return live[id].dead==true end
function DeleteEntity(id) live[id]=nil end
function SetEntityAsMissionEntity(id) live[id].mission=true end
function SetEntityCoordsNoOffset(id,x,y,z) live[id].x,live[id].y,live[id].z=x,y,z end
function SetEntityInvincible(id,v) live[id].invincible=v end
function SetEntityCanBeDamaged() end
function SetPedCanRagdoll() end
function FreezeEntityPosition(id,v) live[id].frozen=v end
function SetBlockingOfNonTemporaryEvents() end
function SetModelAsNoLongerNeeded() end
local function frame()
    local ok,err=coroutine.resume(tasks[1]) assert(ok,err)
    for i=2,#tasks do if coroutine.status(tasks[i])~='dead' then local done,message=coroutine.resume(tasks[i]) assert(done,message) end end
end
function runTreasureSpecs()
    frame() frame()
    local id,ped=next(live) assert(ped and ped.mission and ped.invincible and ped.frozen and ped.z==10)
    local options=targets[id] assert(options[1].label=='報酬を受け取る')
    options[1].onSelect() assert(claims==1 and notices[#notices]=='Received','target triggers reward claim')
    options[1].onSelect() assert(claims==2 and notices[#notices]=='Already received','server rejection is shown')
    live[id]=nil frame() local replacement=next(live)
    assert(replacement and replacement~=id and targets[replacement] and not targets[id],'missing NPC is recreated with target')
    SeatingClient.openTreasures()
    contexts.omnite_treasures.options[2].onSelect()
    contexts.omnite_treasure_edit.options[2].onSelect()
    assert(opened.kind=='stash' and opened.id=='reward_stash','manager opens reward stash')
    contexts.omnite_treasure_edit.options[3].onSelect()
    assert(contexts.omnite_treasure_reviews.options[1].disabled,'empty uncertainty list is explained')
    SeatingClient.openTreasures() contexts.omnite_treasures.options[1].onSelect()
    assert(save.name=='New treasure' and save.model=='test_ped' and save.enabled and save.relocate,'manager can place NPC')
    position.x=200 frame() assert(next(live)==nil and next(targets)==nil,'far NPC is cleaned')
    position.x=1 frame() assert(next(live),'NPC returns on approach')
    point.enabled=false events['ptech_omnite_toolbox:treasure:state'](points) frame()
    assert(next(live)==nil,'disabled NPC is not shown')
    point.enabled=true modelFail=true frame() assert(next(live)==nil)
    modelFail=false frame() assert(next(live),'failed model load is retried')
    events['QBCore:Client:OnPlayerUnload']() frame() assert(next(live)==nil and next(targets)==nil)
    events['ptech_omnite_toolbox:treasure:state'](points) frame() assert(next(live)==nil)
    events['QBCore:Client:OnPlayerLoaded']() frame() assert(next(live))
    events.onResourceStop('test') assert(next(live)==nil and next(targets)==nil)
end
