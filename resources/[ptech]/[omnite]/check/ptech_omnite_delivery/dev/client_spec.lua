-- FiveM client does not expose the os library.
os=nil
function GetCloudTimeAsInt() return 100000 end
local threads, events, exportsList, contexts = {}, {}, {}, {}
local markers, routes, targets, deleted = {}, {}, {}, {}
local state, callbackResult, selected, clipboard
local openedInventory, dialog
local inputResponse, savedLocation
local spawned, rewardChange = {},nil
local positioned={}
local missing,missionEntities={},{}
local failTargetOnce=false
local handoverResult=true
DeliveryGameplay={update=function() end,stop=function() end,handover=function() return handoverResult end}
local position={x=0,y=0,z=0}
local role={name='diner',isboss=false,onduty=true}
local vectorMt={__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},getmetatable(a)) end,
    __len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},vectorMt) end
function CreateThread(fn) threads[#threads+1]=fn end
function Wait() coroutine.yield() end
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) events[name]=fn end
function PlayerPedId() return 1 end
function GetEntityCoords() return vec3(position.x,position.y,position.z) end
function GetEntityHeading() return 90 end
function IsPedDeadOrDying() return false end
function joaat(value) return value end
function IsModelInCdimage() return true end
function IsModelAPed() return true end
function GetCurrentResourceName() return 'ptech_omnite_delivery' end
function AddBlipForCoord(x,y,z) local id=#markers+1 markers[id]={x=x,y=y,z=z} return id end
function RemoveBlip(id) markers[id].removed=true end
function SetBlipSprite(id,sprite) assert(sprite==478) end
function SetBlipColour() end
function SetBlipRoute(id,on) routes[id]=on end
function BeginTextCommandSetBlipName() end
function AddTextComponentSubstringPlayerName() end
function EndTextCommandSetBlipName() end
function CreatePed(_,model,x,y,z)
    local entity=100+#spawned
    spawned[#spawned+1]={x=x,y=y,z=z,entity=entity}
    return entity
end
function SetEntityAsMissionEntity(entity) missionEntities[entity]=true end
function SetEntityCoordsNoOffset(ped,x,y,z) positioned[#positioned+1]={x=x,y=y,z=z} end
function SetModelAsNoLongerNeeded() end
function SetEntityInvincible() end
function FreezeEntityPosition() end
function SetBlockingOfNonTemporaryEvents() end
function DoesEntityExist(entity) return not missing[entity] and not deleted[entity] end
function DeleteEntity(id) deleted[id]=true end
json={encode=function(p) return p and p.id or '' end}
lib={
    callback={await=function(name,_,...)
        if name:match(':state$') then return state end
        local action,input=...
        if name:match(':manage$') and action=='save' then savedLocation=input end
        if name:match(':vault$') then
            local id,operation,amount=...
            rewardChange={id=id,operation=operation,amount=amount}
        end
        return callbackResult
    end},
    notify=function() end,
    requestModel=function() return 123 end,
    registerContext=function(data) contexts[data.id]=data end,
    showContext=function(id) selected=id end,
    getOpenContextMenu=function() return selected end,
    hideContext=function() selected=nil end,
    inputDialog=function(title,fields)
        dialog={title=title,fields=fields}
        local result=inputResponse inputResponse=nil return result
    end,
    setClipboard=function(text) clipboard=text end,
}
exports=setmetatable({
    ox_inventory={openInventory=function(_,kind,data) openedInventory={kind=kind,data=data} return true end},
    qbx_core={GetPlayerData=function() return {job=role} end},
    ox_target={
        addLocalEntity=function(_,ped,options)
            if failTargetOnce then failTargetOnce=false error('test target registration failure') end
            targets[options[1].name]=options[1]
        end,
        removeLocalEntity=function(_,ped) end,
    },
},{__call=function(_,name,fn) exportsList[name]=fn end})
function runClientSpecs()
    local prefix='ptech_omnite_delivery:'
    local points={shop={id='shop',kind='shop',label='Diner',job='diner',reward=100,points=1,coords={x=0,y=0,z=0},heading=0},
        pickup={id='pickup',kind='pickup',label='Pickup',coords={x=10,y=0,z=0},heading=0},
        pickup2={id='pickup2',kind='pickup',label='Other pickup',coords={x=20,y=0,z=0},heading=0}
}
    for _,point in pairs(points) do point.bucket=0 end
    state={ok=true,locations=points,manager=true}
    events['QBCore:Client:OnPlayerLoaded']()
    local loop=coroutine.create(threads[1])
    assert(coroutine.resume(loop))
    for i=3,#threads do threads[i]() end
    local shop,pickup=targets[prefix..'shop'],targets[prefix..'pickup']
    assert(shop and not pickup and not targets[prefix..'pickup2'],'before accepting only store NPC is spawned')
    assert(#spawned==1 and spawned[1].z==0,'do not subtract model height from saved player center')
    assert(#positioned==1 and positioned[1].z==0,'place exact saved center with no native offset before freezing')
    assert(missionEntities[spawned[1].entity],'NPCs are protected mission entities')
    assert(shop.canInteract())
    role.name='other' assert(not shop.canInteract()) role.name='diner'
    role.onduty=false assert(shop.canInteract(),'off-duty employees can interact')
    callbackResult={ok=true,points=5}
    shop.onSelect()
    assert(selected=='omnite_delivery_shop')
    assert(#contexts.omnite_delivery_shop.options==3,'ordinary employees have no reward settings')
    callbackResult={ok=true,points=5,boss=true,reward=400000,vault=800000}
    shop.onSelect()
    inputResponse={250000}
    contexts.omnite_delivery_shop.options[4].onSelect()
    assert(rewardChange.id=='shop' and rewardChange.operation=='reward' and rewardChange.amount==250000,'boss reward option submits chosen amount')
    assert(dialog.fields[1].default==400000,'boss sees the current reward')
    local m={shop='shop',pickup='pickup',picked=false,expires=GetCloudTimeAsInt()+100}
    callbackResult={ok=true,mission=m}
    contexts.omnite_delivery_shop.options[1].onSelect()
    assert(markers[#markers].x==10 and routes[#markers],'start routes to pickup')
    local acceptedQueue=#threads
    assert(coroutine.resume(loop),'NPC streaming must continue after accepting a mission without os')
    for index=acceptedQueue+1,#threads do threads[index]() end
    pickup=targets[prefix..'pickup']
    local pickupEntity=spawned[#spawned].entity
    assert(pickup and pickup.canInteract() and not targets[prefix..'pickup2'],'only assigned destination appears for accepted mission')
    m={shop='shop',pickup='pickup',picked=true,expires=GetCloudTimeAsInt()+100}
    callbackResult={ok=true,mission=m}
    handoverResult=false
    local prior=#markers
    pickup.onSelect()
    assert(#markers==prior and pickup.canInteract(),'cancelled handover leaves mission unchanged')
    handoverResult=true
    pickup.onSelect()
    assert(markers[#markers].x==0 and markers[#markers-1].removed,'pickup switches route to store')
    assert(not pickup.canInteract(),'collected box cannot be picked twice')
    assert(deleted[pickupEntity],'box collection immediately removes the personal destination NPC')
    callbackResult={ok=true,points=5,mission=m}
    shop.onSelect()
    assert(not contexts.omnite_delivery_shop.options[2].disabled)
    callbackResult={ok=true,reward=100,points=1}
    contexts.omnite_delivery_shop.options[2].onSelect()
    assert(markers[#markers].removed,'completion clears route')
    exportsList.openManager()
    assert(selected=='omnite_delivery_manager' and #contexts.omnite_delivery_manager.options==8)
    local options=contexts.omnite_delivery_manager.options
    options[1].onSelect() assert(#dialog.fields==5 and dialog.title:find('配達先NPC'),'destination includes visibility and NPC model')
    assert(dialog.fields[4].default=='mission' and #dialog.fields[4].options==2,'old destinations default to mission visibility')
    options[2].onSelect() assert(#dialog.fields==6 and dialog.fields[4].required and dialog.title:find('店舗NPC'),'placement includes job, points and model; reward belongs to boss')
    callbackResult={ok=true,products={{id='normal',item='pomnite_food_supply',label='Food',cash=9000,points=2}},revision=2,
        items={{value='pomnite_food_supply',label='Food'}}}
    contexts.omnite_delivery_manager.options[3].onSelect()
    assert(selected=='omnite_delivery_product_manager','toolbox manager opens product settings')
    contexts.omnite_delivery_product_manager.options[1].onSelect()
    assert(#dialog.fields==4 and dialog.fields[2].searchable,'product editor selects installed items and prices')
    points.shop.model='s_m_m_business_01'
    local exportPickup={id='export_pickup',label='Export',kind='pickup',bucket=0,coords={x=1,y=2,z=3},heading=0,visibility='always'}
    callbackResult={ok=true,locations={points.shop,exportPickup}}
    contexts.omnite_delivery_manager.options[5].onSelect()
    assert(clipboard:find('Config.locations') and clipboard:find('job="diner"'),'config export includes job')
    local oldLocations=Config.locations
    assert(load(clipboard))()
    assert(Config.locations[1].model=='s_m_m_business_01','config export preserves individual NPC models')
    assert(Config.locations[2].visibility=='always','config export preserves destination visibility')
    Config.locations=oldLocations
    inputResponse={'new_pickup','New destination',true,'always','s_m_m_dockwork_01'}
    callbackResult={ok=true}
    contexts.omnite_delivery_manager.options[1].onSelect()
    assert(savedLocation.kind=='pickup' and savedLocation.model=='s_m_m_dockwork_01')
    assert(savedLocation.visibility=='always','destination form saves selected visibility')
    assert(savedLocation.job==nil and savedLocation.reward==nil and savedLocation.points==nil,'destination model is not submitted as a shop job')
    local previousSpawn=#spawned
    missing[spawned[1].entity]=true
    local queued=#threads
    assert(coroutine.resume(loop))
    for index=queued+1,#threads do threads[index]() end
    assert(#spawned==previousSpawn+1,'missing NPC is recreated while player stays nearby')
    previousSpawn=#spawned
    missing[spawned[#spawned].entity]=true
    queued=#threads failTargetOnce=true
    assert(coroutine.resume(loop))
    for index=queued+1,#threads do threads[index]() end
    assert(deleted[spawned[#spawned].entity],'failed target setup cleans up partially created NPC')
    queued=#threads
    assert(coroutine.resume(loop))
    for index=queued+1,#threads do threads[index]() end
    assert(#spawned==previousSpawn+2,'spawn errors do not leave a permanent loading cache')
    -- Cancel after a spawn is queued, before the model load thread executes.
    state.mission={token='queued',shop='shop',pickup='pickup',picked=false,expires=GetCloudTimeAsInt()+100}
    events['QBCore:Client:OnPlayerLoaded']()
    local beforeCancel=#spawned
    queued=#threads assert(coroutine.resume(loop))
    state.mission=nil events['QBCore:Client:OnPlayerLoaded']()
    for index=queued+1,#threads do threads[index]() end
    assert(#spawned==beforeCancel,'cancelled queued spawn cannot leave a destination NPC behind')
    points.pickup2.visibility='always'
    events[prefix..'locations'](points)
    local beforeAlways=#spawned
    queued=#threads assert(coroutine.resume(loop))
    for index=queued+1,#threads do threads[index]() end
    assert(#spawned==beforeAlways+1,'always-visible destination appears without accepting')
    local permanent=spawned[#spawned].entity
    assert(not targets[prefix..'pickup2'].canInteract(),'always visible does not allow unauthorized collection')
    points.pickup2.visibility='mission'
    events[prefix..'locations'](points)
    assert(coroutine.resume(loop))
    assert(deleted[permanent],'switching back to mission hides destination for non-accepting player')
    events[prefix..'locations']({})
    assert(deleted[spawned[#spawned].entity],'removed locations clean up NPC entities')
    events.onResourceStop('ptech_omnite_delivery')
    assert(selected==nil,'resource stop closes its menus')
end
