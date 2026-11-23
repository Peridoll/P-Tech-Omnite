local callbacks,events,rows={},{},{}
local init,dbFail
local now,nextId=1000,1
local positions={[1]={x=0,y=0,z=10},[2]={x=0,y=0,z=10}}
local buckets={[1]=0,[2]=0}
local tools={[1]=true,[2]=false}
local metadata,states,seated,vehicles={},{},{},{}
local prefix='ptech_omnite_toolbox:teleport:'
function vec3(x,y,z) return {x=x,y=y,z=z} end
function GetGameTimer() return now end
function GetPlayerPed(src) return positions[src] and src or 0 end
function GetEntityCoords(ped) return positions[ped] end
function GetEntityHeading() return 123 end
function GetEntityHealth() return 200 end
function GetVehiclePedIsIn(ped) return vehicles[ped] and 10 or 0 end
function GetPlayerRoutingBucket(src) return buckets[src] end
function GetPlayers() return {'1','2'} end
function Player(src) return {state=states[src] or {}} end
function TriggerClientEvent() end
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) events[name]=fn end
json={encode=function(p) return p end,decode=function(p) return p end}
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
exports={qbx_core={GetPlayer=function(_,src) return {PlayerData={citizenid='owner'..src,metadata=metadata[src] or {}}} end},
    ox_inventory={GetItemCount=function(_,src) return tools[src] and 1 or 0 end}}
SeatingServer={
    finite=function(n,max) return type(n)=='number' and n==n and math.abs(n)<=max end,
    hasSeat=function(src) return seated[src] end,
    near=function(src,p,d)
        local c=positions[src]
        return (c.x-p.x)^2+(c.y-p.y)^2+(c.z-p.z)^2<=d*d
    end,
}
MySQL={ready=function(fn) init=fn end,
    query={await=function(sql) return sql:find('SELECT') and rows or {} end},
    insert={await=function(_,params)
        if dbFail then error('DB offline') end
        local id=nextId nextId=nextId+1
        rows[#rows+1]={id=id,owner=params[1],payload=params[2],bucket=params[3],revision=1}
        return id
    end},
    update={await=function(sql,params)
        if dbFail then error('DB offline') end
        local deleting=sql:find('DELETE')
        local id,rev=deleting and params[1] or params[2],deleting and params[2] or params[3]
        for i,p in ipairs(rows) do if tostring(p.id)==id and p.revision==rev then
            if deleting then table.remove(rows,i) else p.payload=params[1] p.revision=p.revision+1 end
            return 1
        end end
        return 0
    end}}
local function invoke(src,action,...)
    now=now+500
    return callbacks[prefix..action](src,...)
end
function runTeleportSpecs()
    assert(not invoke(1,'begin').ok,'DB readiness gates creation')
    init()
    assert(not invoke(2,'begin').ok,'tool required to manage')
    local draft=invoke(1,'begin')
    assert(draft.ok and not draft.a and not draft.b)
    assert(not invoke(1,'save',draft.token,'入口','both').ok,'two captured endpoints required')
    assert(invoke(1,'capture',draft.token,'a').point.x==0)
    positions[1]={x=100,y=50,z=25}
    buckets[1]=1
    assert(not invoke(1,'capture',draft.token,'b').ok,'cross-bucket capture rejected')
    buckets[1]=0
    vehicles[1]=true assert(not invoke(1,'capture',draft.token,'b').ok,'vehicle capture rejected') vehicles[1]=false
    assert(invoke(1,'capture',draft.token,'b').point.heading==123,'server records current position and heading')
    assert(not invoke(1,'save',draft.token,'入口','forged').ok,'invalid direction rejected')
    dbFail=true assert(not invoke(1,'save',draft.token,'入口','a_to_b').ok,'DB error retains unsaved draft') dbFail=false
    local saved=invoke(1,'save',draft.token,'入口','a_to_b')
    assert(saved.ok and rows[1].payload.b.x==100)
    assert(not invoke(1,'save',draft.token,'重複','both').ok,'saved token cannot create duplicate')
    local id=saved.id
    assert(not invoke(2,'use',id,'b',1).ok,'one-way exit cannot be used in reverse')
    positions[2]={x=500,y=0,z=0}
    assert(not invoke(2,'use',id,'a',1).ok,'remote use rejected')
    positions[2]={x=0,y=0,z=10}
    buckets[2]=1 assert(not invoke(2,'use',id,'a',1).ok,'bucket isolation') buckets[2]=0
    seated[2]=true assert(not invoke(2,'use',id,'a',1).ok,'seated use rejected') seated[2]=false
    metadata[2]={isdead=true} assert(not invoke(2,'use',id,'a',1).ok,'dead use rejected') metadata[2]={}
    states[2]={emsEscortedBy=1} assert(not invoke(2,'use',id,'a',1).ok,'carried use rejected') states[2]={}
    local used=invoke(2,'use',id,'a',1)
    assert(used.ok and used.destination.x==100 and used.destination.heading==123,'ordinary players without tool use trusted destination')
    assert(not invoke(2,'use',id,'a',1).ok,'cooldown prevents repeated travel')
    tools[2]=true
    local edit=invoke(2,'begin',id,1)
    assert(edit.ok and edit.a.x==0 and edit.b.x==100,'other tool holder can edit saved endpoints')
    assert(invoke(2,'save',edit.token,'双方向','both').ok)
    assert(not invoke(1,'use',id,'b',1).ok,'stale revision rejected')
    now=now+3000
    assert(invoke(1,'use',id,'b',2).destination.x==0,'bidirectional B to A works')
    local reverse=invoke(2,'begin',id,2)
    assert(invoke(2,'save',reverse.token,'逆向き','b_to_a').ok)
    now=now+3000
    positions[1]={x=0,y=0,z=10}
    assert(not invoke(1,'use',id,'a',3).ok,'B to A mode rejects A entry')
    init()
    assert(invoke(1,'list').points[id].mode=='b_to_a','restart restores endpoints and direction')
    assert(not invoke(2,'delete',id,1).ok,'stale delete rejected')
    dbFail=true assert(not invoke(2,'delete',id,3).ok,'failed delete retains saved point') dbFail=false
    assert(invoke(2,'delete',id,3).ok,'any tool holder can delete')
    assert(not invoke(1,'list').points[id],'deleted point no longer published')
    local cancelled=invoke(1,'begin')
    source=1 events[prefix..'cancel'](cancelled.token)
    assert(not invoke(1,'capture',cancelled.token,'a').ok,'cancel invalidates token')
    local expired=invoke(1,'begin')
    now=now+Config.Teleporters.draftLifetime+1
    assert(not invoke(1,'capture',expired.token,'a').ok,'expired drafts rejected')
end
