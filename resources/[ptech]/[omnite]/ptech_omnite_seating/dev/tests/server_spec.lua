local mt = {}
mt.__sub = function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end
mt.__len = function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local positions = { [1]=vec3(0,0,0), [2]=vec3(0,0,0) }
local buckets = { [1]=0,[2]=0 }
local identities = { [1]='owner1',[2]='owner2' }
local tools, ems, admins = { [1]=true,[2]=true }, {}, {}
local callbacks, events, commands, exported = {}, {}, {}, {}
local ready, nextId, dbFail, duringUpdate = nil, 1, false, nil
local dbRows, sent = {}, {}
function GetPlayerPed(src) return positions[src] and src or 0 end
function GetEntityCoords(ped) return positions[ped] end
function GetPlayerRoutingBucket(src) return buckets[src] end
function GetPlayers() return {'1','2'} end
function GetGameTimer() return 100000 end
function GetResourceState() return 'started' end
function GetInvokingResource() return 'ptech_mediora_medical' end
function IsPlayerAceAllowed(src) return admins[src] == true end
function joaat() return 123 end
function RegisterNetEvent(name,handler) events[name]=handler end
function AddEventHandler(name,handler)
    local previous=events[name]
    events[name]=function(...) if previous then previous(...) end handler(...) end
end
function RegisterCommand(name,handler,restricted) commands[name]={handler,restricted} end
function CreateThread() end
function TriggerClientEvent(...) sent[#sent+1]={...} end
function TriggerEvent() end
json = {encode=function(t) return t end,decode=function(t) return t end}
lib = {callback={register=function(name,handler) callbacks[name]=handler end}}
exports = setmetatable({
    qbx_core = {GetPlayer=function(_,src) return {PlayerData={citizenid=identities[src],job={name=ems[src] and 'ambulance' or 'mechanic'}}} end},
    ox_inventory = {GetItemCount=function(_,src) return tools[src] and 1 or 0 end,AddItem=function() return true end},
}, {__call=function(_,name,handler) exported[name]=handler end})
MySQL = {
    ready=function(fn) ready=fn end,
    query={await=function(sql) if sql:find('SELECT') then return dbRows end return {} end},
    insert={await=function(sql,params)
        if dbFail then error('offline') end
        local id=nextId nextId=nextId+1
        dbRows[#dbRows+1]={id=id,owner=params[1],mlo=params[2],name=params[3],kind=params[4],payload=params[5],bucket=params[6],revision=1}
        return id
    end},
    update={await=function(sql,params)
        if duringUpdate then duringUpdate() end
        if dbFail then error('offline') end
        local deleting=sql:find('DELETE')
        local id,revision=deleting and params[1] or params[5],deleting and params[2] or params[6]
        for i,row in ipairs(dbRows) do
            if tostring(row.id)==tostring(id) and row.revision==revision then
                if deleting then table.remove(dbRows,i) else row.payload=params[4] row.revision=revision+1 end
                return 1
            end
        end
        return 0
    end},
}

local prefix='ptech_omnite_seating:'
local function invoke(src,action,...) return callbacks[prefix..action](src,...) end
local function input(kind)
    return {mlo='pillbox',name='waiting_01',kind=kind or 'chair',coords={x=0,y=0,z=0},heading=90,style='standard'}
end
local function tick(src) source=src events['playerDropped']() end

function runSpecs()
    local S=SeatingServer
    assert(not invoke(1,'tool').ok,'DB readiness required')
    ready()
    assert(S.ready and invoke(1,'tool').ok)
    tools[1]=false assert(not invoke(1,'save',input()).ok,'missing tool') tools[1]=true
    assert(not invoke(1,'save',input('patient_bed')).ok,'non EMS denied') tick(1)
    local bad=input() bad.coords.x=0/0
    assert(not invoke(1,'save',bad).ok,'NaN denied') tick(1)
    bad=input() bad.coords.x=99
    assert(not invoke(1,'save',bad).ok,'distance denied') tick(1)
    dbFail=true
    assert(not invoke(1,'save',input()).ok and next(S.placed)==nil,'failed DB never published')
    dbFail=false tick(1)
    local saved=invoke(1,'save',input())
    assert(saved.ok and S.placed[saved.id].owner=='owner1')
    local id=saved.id
    tick(1)
    local edit=input() edit.id=id edit.revision=1
    assert(not invoke(2,'save',edit).ok,'other owner cannot edit') tick(2)
    edit.revision=0
    assert(not invoke(1,'save',edit).ok,'stale revision rejected') tick(1)
    edit.revision=1
    assert(S.claim(1,{key='db:'..id}))
    assert(not S.claim(2,{key='db:'..id}),'single occupancy')
    assert(not invoke(1,'save',edit).ok,'occupied seats cannot change') tick(1)
    assert(S.claim(2,{key='db:'..id}),'disconnect releases lock') S.release(2)
    buckets[2]=1
    assert(not S.claim(2,{key='db:'..id}),'routing bucket isolation') buckets[2]=0
    duringUpdate=function() assert(not S.claim(2,{key='db:'..id}),'no sitting during DB write') end
    edit.heading=180
    assert(invoke(1,'save',edit).ok and S.placed[id].revision==2)
    duringUpdate=nil tick(1)
    Config.FixedSeats={{id='far',coords=vec3(500,0,0)}}
    assert(not S.claim(1,{key='fixed:far',coords={x=0,y=0,z=0}}),'fixed coordinate forgery rejected')
    assert(not S.claim(1,{key='prop:999:0.000:0.000:0.000'}),'unregistered model rejected')
    assert(not S.claim(1,{key='forged'}),'unknown keys rejected')
    assert(S.claim(1,{key='prop:123:0.000:0.000:0.000'}))
    assert(not S.claim(2,{key='db:'..id}),'overlapping keys share exclusion') S.release(1)
    assert(not invoke(1,'export').ok,'admin export only') admins[1]=true
    assert(invoke(1,'export','pillbox').text:find('Config.FixedSeats',1,true))
    ems[1]=true
    local bed=invoke(1,'save',input('patient_bed'))
    assert(bed.ok and exported.GetPatientBeds()[bed.id]) tick(1)
    local deletion={id=bed.id,revision=1}
    ems[1]=false
    assert(not invoke(1,'delete',deletion).ok,'patient edit needs EMS even for admin') tick(1)
    ems[1]=true
    assert(not invoke(2,'placePatient',1,bed.id).ok,'non EMS patient transfer rejected')
    assert(invoke(1,'placePatient',2,bed.id).ok,'EMS patient transfer shares seat lock')
    assert(not S.claim(1,{key='db:'..bed.id}),'patient transfer occupies bed')
    S.release(2)
    dbFail=true assert(not invoke(1,'delete',deletion).ok and S.placed[bed.id],'delete DB failure retains seat') dbFail=false tick(1)
    assert(invoke(1,'delete',deletion).ok and not S.placed[bed.id])
    S.placed={} S.ready=false ready()
    assert(S.placed[id] and S.placed[id].heading==180,'restart restores DB state')
    assert(commands.omnite_seatdebug[2] and commands.omnite_seatghost[2],'debug commands restricted server-side')
    local before=#sent
    events['ox_inventory:usedItem'](1,Config.Placement.item)
    assert(#sent==before+1,'non-consumable inventory use opens tool')
    tools[1]=false
    events['ox_inventory:usedItem'](1,Config.Placement.item)
    assert(#sent==before+1,'inventory completion rechecks possession')
end
