local threads, events, exportsList, contexts = {}, {}, {}, {}
local markers, routes, targets, deleted = {}, {}, {}, {}
local state, callbackResult, selected, clipboard
local openedInventory, dialog
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
function GetCurrentResourceName() return 'ptech_omnite_delivery' end
function AddBlipForCoord(x,y,z) local id=#markers+1 markers[id]={x=x,y=y,z=z} return id end
function RemoveBlip(id) markers[id].removed=true end
function SetBlipSprite(id,sprite) assert(sprite==478) end
function SetBlipColour() end
function SetBlipRoute(id,on) routes[id]=on end
function BeginTextCommandSetBlipName() end
function AddTextComponentSubstringPlayerName() end
function EndTextCommandSetBlipName() end
function CreatePed() return 42 end
function SetModelAsNoLongerNeeded() end
function SetEntityInvincible() end
function FreezeEntityPosition() end
function SetBlockingOfNonTemporaryEvents() end
function DoesEntityExist() return true end
function DeleteEntity(id) deleted[id]=true end
json={encode=function(p) return p and p.id or '' end}
lib={
    callback={await=function(name,_,...)
        if name:match(':state$') then return state end
        return callbackResult
    end},
    notify=function() end,
    requestModel=function() return 123 end,
    registerContext=function(data) contexts[data.id]=data end,
    showContext=function(id) selected=id end,
    getOpenContextMenu=function() return selected end,
    hideContext=function() selected=nil end,
    inputDialog=function(title,fields) dialog={title=title,fields=fields} return nil end,
    setClipboard=function(text) clipboard=text end,
}
exports=setmetatable({
    ox_inventory={openInventory=function(_,kind,data) openedInventory={kind=kind,data=data} return true end},
    qbx_core={GetPlayerData=function() return {job=role} end},
    ox_target={
        addLocalEntity=function(_,ped,options) targets[options[1].name]=options[1] end,
        removeLocalEntity=function(_,ped) end,
    },
},{__call=function(_,name,fn) exportsList[name]=fn end})
function runClientSpecs()
    local prefix='ptech_omnite_delivery:'
    local points={shop={id='shop',kind='shop',label='Diner',job='diner',reward=100,points=1,coords={x=0,y=0,z=0},heading=0},
        pickup={id='pickup',kind='pickup',label='Pickup',coords={x=10,y=0,z=0},heading=0}
}
    for _,point in pairs(points) do point.bucket=0 end
    state={ok=true,locations=points,manager=true}
    events['QBCore:Client:OnPlayerLoaded']()
    local loop=coroutine.create(threads[1])
    assert(coroutine.resume(loop))
    for i=3,#threads do threads[i]() end
    local shop,pickup=targets[prefix..'shop'],targets[prefix..'pickup']
    assert(shop and pickup,'store and destination NPC targets registered')
    assert(shop.canInteract() and not pickup.canInteract())
    role.name='other' assert(not shop.canInteract()) role.name='diner'
    role.onduty=false assert(shop.canInteract(),'off-duty employees can interact')
    callbackResult={ok=true,points=5}
    shop.onSelect()
    assert(selected=='omnite_delivery_shop')
    local m={shop='shop',pickup='pickup',picked=false,expires=os.time()+100}
    callbackResult={ok=true,mission=m}
    contexts.omnite_delivery_shop.options[1].onSelect()
    assert(markers[#markers].x==10 and routes[#markers],'start routes to pickup')
    assert(pickup.canInteract(),'only assigned pickup is usable')
    m={shop='shop',pickup='pickup',picked=true,expires=os.time()+100}
    callbackResult={ok=true,mission=m}
    handoverResult=false
    local prior=#markers
    pickup.onSelect()
    assert(#markers==prior and pickup.canInteract(),'cancelled handover leaves mission unchanged')
    handoverResult=true
    pickup.onSelect()
    assert(markers[#markers].x==0 and markers[#markers-1].removed,'pickup switches route to store')
    assert(not pickup.canInteract(),'collected box cannot be picked twice')
    callbackResult={ok=true,points=5,mission=m}
    shop.onSelect()
    assert(not contexts.omnite_delivery_shop.options[2].disabled)
    callbackResult={ok=true,reward=100,points=1}
    contexts.omnite_delivery_shop.options[2].onSelect()
    assert(markers[#markers].removed,'completion clears route')
    exportsList.openManager()
    assert(selected=='omnite_delivery_manager' and #contexts.omnite_delivery_manager.options==7)
    local options=contexts.omnite_delivery_manager.options
    options[1].onSelect() assert(#dialog.fields==4 and dialog.title:find('配達先NPC'),'destination includes NPC model')
    options[2].onSelect() assert(#dialog.fields==7 and dialog.fields[4].required and dialog.title:find('店舗NPC'),'store includes job, rewards and model')
    callbackResult={ok=true,products={{id='normal',item='pomnite_food_supply',label='Food',cash=9000,points=2}},revision=2,
        items={{value='pomnite_food_supply',label='Food'}}}
    contexts.omnite_delivery_manager.options[3].onSelect()
    assert(selected=='omnite_delivery_product_manager','toolbox manager opens product settings')
    contexts.omnite_delivery_product_manager.options[1].onSelect()
    assert(#dialog.fields==4 and dialog.fields[2].searchable,'product editor selects installed items and prices')
    callbackResult={ok=true,locations={points.shop}}
    contexts.omnite_delivery_manager.options[5].onSelect()
    assert(clipboard:find('Config.locations') and clipboard:find('job="diner"'),'config export includes job')
    events[prefix..'locations']({})
    assert(deleted[42],'removed locations clean up NPC entities')
    events.onResourceStop('ptech_omnite_delivery')
    assert(selected==nil,'resource stop closes its menus')
end
