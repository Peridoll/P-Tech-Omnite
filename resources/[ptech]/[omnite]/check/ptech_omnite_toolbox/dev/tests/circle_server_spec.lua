local callbacks,events,rows={},{},{}
local init,dbFail
local now,nextId=1000,1
local positions={[1]={x=0,y=0,z=10},[2]={x=200,y=0,z=10}}
local buckets={[1]=0,[2]=0}
local moves,warnings={},{}
local prefix='ptech_omnite_toolbox:circle:'
function vec3(x,y,z) return {x=x,y=y,z=z} end
function GetGameTimer() return now end
function GetPlayerPed(src) return positions[src] and src or 0 end
function GetEntityCoords(ped) return positions[ped] end
function GetEntityHeading() return 123 end
function GetVehiclePedIsIn() return 0 end
function GetPlayerRoutingBucket(src) return buckets[src] end
function GetPlayers() return {'1','2'} end
local adminPermission = 'admin'
function IsPlayerAceAllowed(src, permission) return src==1 and permission==adminPermission end
function SetEntityCoords(ped,x,y,z) positions[ped]={x=x,y=y,z=z} moves[ped]=(moves[ped] or 0)+1 end
function SetEntityHeading() end
function TriggerClientEvent(name,src,id,active)
    if name==prefix..'warning' then warnings[src]=active end
end
function CreateThread() end
function AddEventHandler(name,fn) events[name]=fn end
json={encode=function(p) return p end,decode=function(p) return p end}
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
SeatingServer={
    release=function() end,hasSeat=function() return false end,
    finite=function(n,max) return type(n)=='number' and n==n and math.abs(n)<=max end,
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
        rows[#rows+1]={id=id,payload=params[1],bucket=params[2],revision=1}
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
    now=now+1000
    return callbacks[prefix..action](src,...)
end
local function tick(ms) now=now+(ms or 250) SeatingServer.tickCircles() end
function runCircleSpecs()
    assert(callbacks[prefix..'capture'](1).ok, 'Qbox admin can configure circles')
    adminPermission='god'
    assert(callbacks[prefix..'capture'](1).ok, 'Qbox god can configure circles')
    adminPermission=Config.Placement.adminAce
    assert(callbacks[prefix..'capture'](1).ok, 'dedicated ACE can configure circles')
    adminPermission='admin'
    assert(not invoke(1,'list').ok,'DB readiness')
    init()
    local p={name='Circle',center={x=0,y=0,z=10,heading=0},destination={x=0,y=0,z=10,heading=90},
        radius=50,delay=10,message='Return in {seconds}',enabled=true}
    assert(not invoke(2,'save',p).ok,'non-admin cannot create')
    assert(not invoke(2,'capture').ok,'non-admin cannot capture')
    assert(invoke(1,'capture').point.heading==123)
    p.radius=0/0 assert(not invoke(1,'save',p).ok,'NaN rejected') p.radius=50
    p.destination.x=60 assert(not invoke(1,'save',p).ok,'destination must be inside') p.destination.x=0
    dbFail=true assert(not invoke(1,'save',p).ok,'failed persistence does not publish') dbFail=false
    local saved=invoke(1,'save',p) assert(saved.ok)
    p.id,p.revision=saved.id,1
    assert(invoke(1,'appearance',p.id).ok,'inside active circle can open initial appearance')
    assert(not invoke(2,'appearance',p.id).ok,'outside circle cannot open initial appearance')
    buckets[1]=1 assert(not invoke(1,'appearance',p.id).ok,'other bucket cannot open initial appearance') buckets[1]=0
    local list=invoke(2,'list')
    assert(list.ok and not list.admin and list.points[p.id],'ordinary player gets interaction state')
    assert(list.points[p.id].kind=='starter','legacy circle defaults to starter')
    assert(not list.points[p.id].password,'password not public')
    assert(not invoke(2,'delete',p.id,1).ok,'non-admin cannot delete')
    tick() tick(12000) assert(not moves[2],'players who never entered are not constrained')
    positions[2]={x=10,y=0,z=1000} tick()
    positions[2]={x=60,y=0,z=10} tick()
    assert(warnings[2],'circular XY boundary starts countdown')
    tick(9000) assert(not moves[2],'delay respected')
    positions[2]={x=49,y=0,z=10} tick()
    assert(warnings[2]==false,'reentry cancels countdown')
    positions[2]={x=80,y=0,z=10} tick() tick(10000)
    assert(moves[2]==1 and positions[2].x==0,'expired countdown returns to configured destination')
    positions[2]={x=80,y=0,z=10} tick()
    p.enabled=false assert(invoke(1,'save',p).ok) p.revision=2
    tick(12000) assert(moves[2]==1 and not warnings[2],'disable releases countdown')
    p.enabled=true assert(invoke(1,'save',p).ok) p.revision=3
    positions[2]={x=0,y=0,z=10} tick()
    assert(not invoke(2,'escape',p.id,'wrong').ok,'wrong password')
    assert(not callbacks[prefix..'escape'](2,p.id,'4155').ok,'password attempts rate limited')
    positions[2]={x=100,y=0,z=10}
    assert(not invoke(2,'escape',p.id,'4155').ok,'remote password use rejected')
    positions[2]={x=0,y=0,z=10} buckets[2]=1
    assert(not invoke(2,'escape',p.id,'4155').ok,'cross-bucket escape rejected')
    tick() buckets[2]=0 tick()
    assert(invoke(2,'escape',p.id,'4155').ok,'correct password accepted for non-admin')
    assert(positions[2].x==Config.Circles.escapeDestination.x,'escape goes to Legion')
    tick() tick(12000) assert(moves[2]==2,'escape clears memberships')
    positions[2]={x=0,y=0,z=10} tick()
    positions[2]={x=90,y=0,z=10} tick()
    p.message='Updated' assert(invoke(1,'save',p).ok) p.revision=4
    tick() tick(10000) assert(moves[2]==3,'editing active settings preserves existing membership')
    positions[2]={x=80,y=0,z=10} tick() buckets[2]=1 tick() tick(12000)
    assert(moves[2]==3,'bucket change releases player')
    assert(not invoke(1,'delete',p.id,1).ok,'stale revision rejected')
    init() assert(invoke(1,'list').points[p.id].revision==4,'DB reload restores settings')
    assert(invoke(1,'delete',p.id,4).ok,'admin deletion persists')
    assert(not invoke(1,'list').points[p.id],'deleted circle no longer listed')
    local repel={kind='npc_repellent',name='人除け',center={x=0,y=0,z=10,heading=0},radius=50,enabled=true}
    repel.kind='unknown' assert(not invoke(1,'save',repel).ok,'unknown kind is rejected') repel.kind='npc_repellent'
    assert(not invoke(2,'save',repel).ok,'non-admin cannot create repellent circles')
    local created=invoke(1,'save',repel) assert(created.ok,'repellent needs no destination or countdown')
    local savedRepel=invoke(1,'list').points[created.id]
    assert(savedRepel.kind=='npc_repellent' and not savedRepel.destination and not savedRepel.delay)
    positions[1]={x=0,y=0,z=10}
    assert(not invoke(1,'appearance',created.id).ok,'repellent does not allow appearance editing')
    assert(not invoke(1,'escape',created.id,'4155').ok,'repellent does not provide starter escape')
    buckets[2]=0 positions[2]={x=0,y=0,z=10} tick()
    local before=moves[2]
    positions[2]={x=100,y=0,z=10} tick() tick(12000)
    assert(moves[2]==before and not warnings[2],'repellent never constrains players')
    buckets[1]=1 assert(not invoke(1,'list').points[created.id],'repellent is isolated by bucket') buckets[1]=0
    init() assert(invoke(1,'list').points[created.id].kind=='npc_repellent','repellent kind survives reload')
    assert(invoke(1,'delete',created.id,1).ok,'repellent can be deleted')
end
