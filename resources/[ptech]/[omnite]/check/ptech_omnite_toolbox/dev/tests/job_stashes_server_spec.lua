local callbacks,events,hooks={},{},{}
local init,dbFailure=false,false
local rows,registered,inventories={},{},{}
local sequence=0
local tool=true
local jobs={ambulance={label='EMS'},police={label='Police'}}
local roles={[1]={name='admin',grade={level=0}},[2]={name='ambulance',grade={level=1}},[3]={name='ambulance',grade={level=3}},[4]={name='police',grade={level=4}}}
local positions,buckets={},{}
for i=1,4 do positions[i]={x=1,y=2,z=10} buckets[i]=0 inventories[i]={open=false} end
local closed={}
local function copy(value)
    if type(value)~='table' then return value end
    local result={} for k,v in pairs(value) do result[k]=copy(v) end return result
end
json={encode=copy,decode=copy}
function vec3(x,y,z) return {x=x,y=y,z=z} end
function IsPlayerAceAllowed(src) return src==1 end
function GetPlayerPed(src) return positions[src] and src or 0 end
function GetPlayerRoutingBucket(src) return buckets[src] end
function GetEntityCoords(src) return positions[src] end
function GetPlayers() return {'1','2','3','4'} end
function TriggerClientEvent(name,src) if name=='ox_inventory:closeInventory' then closed[#closed+1]=src end end
function CreateThread() end
function AddEventHandler(name,fn) events[name]=fn end
function RegisterNetEvent(name,fn) events[name]=fn end
function GetCurrentResourceName() return 'test' end
SeatingServer={finite=function(n,max) return type(n)=='number' and n==n and math.abs(n)<=max end}
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
local inv={
    GetItemCount=function() return tool and 1 or 0 end,
    RegisterStash=function(_,id,label,slots,maxWeight,owner,groups,coords,instance)
        assert(owner==false and type(groups)=='table','stash is shared and always has an explicit access rule')
        registered[id]={label=label,slots=slots,maxWeight=maxWeight,owner=owner,groups=copy(groups),coords=copy(coords),instance=instance}
        inventories[id]=inventories[id] or {items={},weight=0,openedBy={}}
        inventories[id].slots=slots inventories[id].maxWeight=maxWeight
    end,
    GetInventory=function(_,id) return inventories[id] end,
    registerHook=function(_,name,fn) hooks[name]=fn end,
}
exports={ox_inventory=inv,qbx_core={GetJobs=function() return jobs end,GetPlayer=function(_,src) return {PlayerData={job=roles[src]}} end}}
MySQL={ready=function(fn) init=fn end,
    query={await=function(sql,args)
        if dbFailure then error('test DB offline') end
        if sql:find('SELECT *',1,true) then local result={} for id,p in pairs(rows) do result[#result+1]={id=id,payload=copy(p)} end return result end
        if sql:find('INSERT INTO',1,true) then rows[args[1]]=copy(args[2]) return 1 end
        return {}
    end},
    scalar={await=function() if dbFailure then error('test DB offline') end sequence=sequence+1 return 'stash'..sequence end},
    update={await=function(_,args)
        if dbFailure then error('test DB offline') end
        if rows[args[1]] then rows[args[1]]=nil return 1 end return 0
    end}}
local prefix='ptech_omnite_toolbox:jobstash:'
local function call(action,src,...) return callbacks[prefix..action](src,...) end
local id,secondId
function runJobStashSpecs()
    assert(not call('list',1,true).ok) init()
    local input={name='EMS Supplies',job='ambulance',minGrade=2,slots=100,maxWeight=500000,enabled=true}
    assert(not call('save',2,input).ok,'non-admin cannot place')
    tool=false assert(not call('save',1,input).ok) tool=true
    input.job='unknown' assert(not call('save',1,input).ok) input.job='ambulance'
    input.slots=1.5 assert(not call('save',1,input).ok) input.slots=100
    input.maxWeight=0/0 assert(not call('save',1,input).ok) input.maxWeight=500000
    dbFailure=true assert(not call('save',1,input).ok) dbFailure=false
    local created=call('save',1,input) assert(created.ok) id=created.id
    local stash=prefix..id local definition=registered[stash]
    assert(definition.groups.ambulance==2 and definition.owner==false and definition.instance==0 and definition.coords.z==10)
    assert(not call('open',2,id).ok,'below grade cannot open') roles[2].grade.level=2
    roles[2].onduty=false
    local a,b=call('open',2,id),call('open',3,id)
    assert(a.ok and b.ok and a.inventory==b.inventory and a.inventory==stash,'members share the same physical stash regardless of duty')
    assert(not call('open',4,id).ok and not call('open',1,id).ok,'wrong job and admin without job cannot use stash')
    assert(hooks.openInventory({source=4,inventoryId=stash})==false)
    assert(hooks.swapItems({source=4,fromInventory=stash,toInventory=4})==false)
    assert(hooks.swapItems({source=2,fromInventory=2,toInventory=stash})~=false)
    positions[2].x=100 assert(not call('open',2,id).ok) positions[2].x=1
    buckets[2]=1 assert(not call('open',2,id).ok) buckets[2]=0
    inventories[2].open=stash roles[2].name='police' source=2
    events[prefix..'checkAccess']()
    assert(closed[#closed]==2 and hooks.swapItems({source=2,fromInventory=stash,toInventory=2})==false,'job loss closes UI and blocks item moves') roles[2].name='ambulance'
    inventories[stash].items[80]={name='water',count=2,slot=80,weight=300}
    inventories[stash].weight=300 inventories[stash].openedBy[2]=true
    local before=call('list',1,true).points[id]
    local update=copy(input) update.id=id update.revision=before.revision update.slots=50
    assert(not call('save',1,update).ok,'sparse occupied slots prevent unsafe shrinking')
    update.slots=100 update.maxWeight=200 assert(not call('save',1,update).ok,'weight prevents unsafe shrinking')
    update.maxWeight=600000 update.name='Renamed' update.coords={x=999,y=999,z=999}
    assert(call('save',1,update).ok)
    local preserved=call('list',1).points[id]
    assert(preserved.coords.x==1 and inventories[stash].items[80].count==2 and registered[stash].label=='Renamed','renaming and capacity edits preserve identity, position and contents')
    assert(closed[#closed]==2,'viewers are closed before changing stash layout')
    assert(not call('save',1,update).ok,'stale edits cannot overwrite')
    update.revision=preserved.revision update.job='police' update.relocate=true positions[1].x=3
    dbFailure=true assert(not call('save',1,update).ok and call('list',1).points[id].job=='ambulance') dbFailure=false
    assert(call('save',1,update).ok)
    assert(not call('open',3,id).ok and call('open',4,id).ok and registered[stash].groups.police==2)
    assert(inventories[stash].items[80].count==2 and call('list',1).points[id].coords.x==3,'move and job edit retain contents')
    local current=call('list',1).points[id]
    update.revision=current.revision update.enabled=false assert(call('save',1,update).ok)
    assert(not call('open',4,id).ok,'disabled stash cannot be opened directly')
    assert(not call('delete',1,id,call('list',1).points[id].revision).ok,'nonempty stash cannot be deleted')
    inventories[stash].items={} inventories[stash].weight=0
    assert(call('delete',1,id,call('list',1).points[id].revision).ok)
    assert(next(registered[stash].groups)==nil,'deleted registered inventory is blocked even after hook reload')
    assert(hooks.openInventory({source=4,inventoryId=stash})==false,'deleted ID remains blocked')
    input.minGrade=0 local second=call('save',1,input) assert(second.ok) secondId=second.id
    assert(secondId~=id and call('open',2,secondId).ok,'new placement has a distinct shared inventory')
    inventories[prefix..secondId].items[1]={name='bandage',count=4,slot=1,weight=40}
    events.onResourceStop('test')
    assert(not call('open',2,secondId).ok and next(registered[prefix..secondId].groups)==nil,'stopping the resource revokes standard inventory access')
end
function runJobStashReloadSpecs()
    init()
    assert(not call('list',1).points[id],'deleted placement stays deleted')
    assert(call('open',2,secondId).inventory==call('open',3,secondId).inventory,'restart preserves the shared ID')
    assert(inventories[prefix..secondId].items[1].count==4,'re-registration does not reset stash contents')
end
