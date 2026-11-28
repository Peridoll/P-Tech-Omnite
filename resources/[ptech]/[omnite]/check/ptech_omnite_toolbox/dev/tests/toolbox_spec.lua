local exported,contexts = {},{}
local useResult,auth,busy = true,true,false
local uses,shown,checks = 0,0,0
local pending
local admin=false
local notices={}
Config={Placement={command='omnite_seating'},Seating={}}
SeatingClient={
    busy=function() return busy end,
    notify=function(message) notices[#notices+1]=message end,
}
lib={
    callback={await=function()
        checks=checks+1
        return auth and {ok=true,ems=false,admin=admin} or {ok=false,message='denied'}
    end},
    registerContext=function(context) contexts[context.id]=context end,
    showContext=function() shown=shown+1 end,
}
exports=setmetatable({ox_inventory={useItem=function(_,data,cb)
    assert(data.name=='pomnite_toolbox')
    uses=uses+1
    if useResult=='pending' then pending=cb else cb(useResult) end
end}},{__call=function(_,name,cb) exported[name]=cb end})
local deliveryState = 'missing'
function GetResourceState() return deliveryState end
function AddEventHandler() end
function RegisterNetEvent() end
function RegisterCommand() end
function RegisterKeyMapping() end
function RegisterNUICallback() end
function CreateThread() end

function runToolboxSpecs()
    local use=exported.usePlacementTool
    local data={name='pomnite_toolbox',slot=1}
    assert(use,'inventory client export registered')
    use(data)
    assert(uses==1 and shown==1 and checks==1,'successful inventory use opens menu after auth')
    assert(contexts.omnite_seat_tool.title=='Omini工具箱')
    assert(#contexts.omnite_seat_tool.options==1 and contexts.omnite_seat_tool.options[1].title=='椅子 & ベッド 管理','ordinary tool holder only sees furniture management')
    useResult=false
    use(data)
    assert(shown==1 and checks==1,'cancelled inventory use never opens menu')
    useResult=true auth=false
    use(data)
    assert(shown==1 and checks==2,'authorization failure never opens menu')
    auth=true busy=true
    local before=uses
    use(data)
    assert(uses==before,'seated or busy cannot start item use')
    busy=false useResult='pending'
    use(data)
    busy=true pending(true)
    assert(shown==1,'becoming busy during use prevents menu')
    busy=false SeatingClient.placing=true
    before=uses use(data)
    assert(uses==before,'placement cannot open another toolbox')
    SeatingClient.placing=false
    useResult=true admin=true
    use(data)
    assert(#contexts.omnite_seat_tool.options==11, 'admin toolbox exposes eleven management modules')
    for _,option in ipairs(contexts.omnite_seat_tool.options) do assert(option.icon~='warehouse','garage management is excluded') end
    assert(contexts.omnite_seat_tool.options[3].title=='サークルエリア管理', 'circle management is visible to admins')
    local shopsOpened=0
    SeatingClient.openShops=function() shopsOpened=shopsOpened+1 end
    contexts.omnite_seat_tool.options[4].onSelect()
    assert(shopsOpened==1,'shop management opens inside toolbox without another resource')
    deliveryState='started'
    use(data)
    assert(#contexts.omnite_seat_tool.options==11,'running delivery exposes admin manager')
    assert(contexts.omnite_seat_tool.options[5].icon=='truck-fast','delivery menu is linked')
    local atm=contexts.omnite_seat_tool.options[6]
    local noticeCount=#notices
    atm.onSelect()
    assert(#notices==noticeCount+1 and notices[#notices]:find('読み込まれていません',1,true),'missing ATM script reports an error instead of silently closing')
    local opened=0
    SeatingClient.openATMs=function() opened=opened+1 end
    atm.onSelect() assert(opened==1,'ATM entry invokes the loaded manager')
    SeatingClient.openATMs=function() error('test ATM failure') end
    noticeCount=#notices atm.onSelect()
    assert(#notices==noticeCount+1,'manager failure is reported to the player')
    noticeCount=#notices contexts.omnite_seat_tool.options[8].onSelect()
    assert(#notices==noticeCount+1,'missing map blip script is reported')
    local mapOpened=0 SeatingClient.openMapBlips=function() mapOpened=mapOpened+1 end
    contexts.omnite_seat_tool.options[8].onSelect() assert(mapOpened==1,'toolbox opens map blip manager')
    noticeCount=#notices contexts.omnite_seat_tool.options[9].onSelect()
    assert(#notices==noticeCount+1,'missing vehicle clone script is reported')
    local clones=0 SeatingClient.cloneVehicle=function() clones=clones+1 end
    contexts.omnite_seat_tool.options[9].onSelect() assert(clones==1,'toolbox invokes vehicle clone')
    noticeCount=#notices contexts.omnite_seat_tool.options[10].onSelect()
    assert(#notices==noticeCount+1,'missing treasure script is reported')
    local openedTreasures=0 SeatingClient.openTreasures=function() openedTreasures=openedTreasures+1 end
    contexts.omnite_seat_tool.options[10].onSelect() assert(openedTreasures==1,'toolbox opens treasure manager')
    noticeCount=#notices contexts.omnite_seat_tool.options[11].onSelect()
    assert(#notices==noticeCount+1,'missing job stash script is reported')
    local openedStashes=0 SeatingClient.openJobStashes=function() openedStashes=openedStashes+1 end
    contexts.omnite_seat_tool.options[11].onSelect() assert(openedStashes==1,'toolbox opens shared stash manager')
end
