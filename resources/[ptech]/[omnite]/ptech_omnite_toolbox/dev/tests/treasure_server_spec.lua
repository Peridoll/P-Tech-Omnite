local callbacks,hooks={},{}
local init
local db={npcs={},claims={}}
local data={[1]={citizenid='one',charinfo={firstname='One'}},[2]={citizenid='two',charinfo={firstname='Two'}}}
local positions={[1]={x=1,y=2,z=10},[2]={x=1,y=2,z=10}}
local buckets={[1]=0,[2]=0}
local tool=true
local nextId=0
local failDB,failCommit,failAdd,throwAdd,onGiving,onAdd=false,false,nil,nil,nil,nil
local additions={}
local inventory={one={slots=20,items={},weight=0,maxWeight=20000},two={slots=20,items={},weight=0,maxWeight=20000}}
local stashes={}
local definitions={water={stack=true,weight=100},bandage={stack=true,weight=50},WEAPON_TEST={stack=false,weight=1000}}
local function copy(t)
    if type(t)~='table' then return t end
    local r={} for k,v in pairs(t) do r[k]=copy(v) end return r
end
local function key(id,citizenid) return id..'/'..citizenid end
json={encode=copy,decode=copy}
function vec3(x,y,z) return {x=x,y=y,z=z} end
function IsPlayerAceAllowed(src) return src==1 end
function GetPlayerPed(src) return positions[src] and src or 0 end
function GetPlayerRoutingBucket(src) return buckets[src] end
function GetEntityCoords(src) return positions[src] end
function GetEntityHeading() return 90 end
function GetPlayers() return {'1','2'} end
function TriggerClientEvent() end
function CreateThread() end
function AddEventHandler() end
SeatingServer={finite=function(n,max) return type(n)=='number' and n==n and math.abs(n)<=max end}
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
local function query(sql,args)
    if failDB then error('test DB offline') end
    if sql:find('SELECT * FROM ptech_omnite_treasures',1,true) then
        local rows={} for id,p in pairs(db.npcs) do rows[#rows+1]={id=id,payload=copy(p)} end return rows
    end
    if sql:find('INSERT INTO ptech_omnite_treasures',1,true) then db.npcs[args[1]]=copy(args[2]) return 1 end
    if sql:find('INSERT IGNORE INTO ptech_omnite_treasure_claims',1,true) then
        local id=key(args[1],args[2])
        if not db.claims[id] then db.claims[id]={npc_id=args[1],citizenid=args[2],display_name=args[3],payload=copy(args[4]),next_index=1,status='ready'} end
        return 1
    end
    if sql:find("status='giving' ORDER BY",1,true) then
        local rows={} for _,p in pairs(db.claims) do if p.npc_id==args[1] and p.status=='giving' then rows[#rows+1]=copy(p) end end return rows
    end
    return {}
end
MySQL={ready=function(fn) init=fn end,query={await=query},
    single={await=function(_,args) if failDB then error('test DB offline') end return copy(db.claims[key(args[1],args[2])]) end},
    scalar={await=function(sql,args)
        if failDB then error('test DB offline') end
        if sql=='SELECT UUID()' then nextId=nextId+1 return 'npc'..nextId end
        local count=0 for _,p in pairs(db.claims) do if p.npc_id==args[1] and p.status~='paid' then count=count+1 end end return count
    end},
    update={await=function(sql,args)
        if failDB then error('test DB offline') end
        if sql:find('DELETE FROM ptech_omnite_treasures',1,true) then if db.npcs[args[1]] then db.npcs[args[1]]=nil return 1 end return 0 end
        if sql:find('SET next_index=',1,true) then
            if failCommit then failCommit=false error('test completion DB failure') end
            local row=db.claims[key(args[3],args[4])]
            if not row or row.status~='giving' or row.next_index~=args[5] then return 0 end
            row.next_index,row.status=args[1],args[2] return 1
        end
        local row=db.claims[key(args[1],args[2])]
        local giving=sql:find("SET status='giving'",1,true)~=nil
        if not row or row.next_index~=args[3] or row.status~=(giving and 'ready' or 'giving') then return 0 end
        row.status=giving and 'giving' or 'ready'
        if giving and onGiving then local fn=onGiving onGiving=nil fn() end
        return 1
    end}}
local inv={
    GetItemCount=function() return tool and 1 or 0 end,
    RegisterStash=function(_,id) stashes[id]=stashes[id] or {} end,
    registerHook=function(_,name,fn) hooks[name]=fn end,
    GetInventoryItems=function(_,id) return stashes[id] end,
    Items=function(_,name) return definitions[name] end,
    GetInventory=function(_,src) return inventory[data[src].citizenid] end,
    CanCarryWeight=function(_,src,weight) local p=inventory[data[src].citizenid] return p and p.weight+weight<=p.maxWeight end,
    CanCarryItem=function(_,src,name,count)
        local p=inventory[data[src].citizenid] local used=0 for _ in pairs(p.items) do used=used+1 end
        return p.weight+definitions[name].weight*count<=p.maxWeight and used<p.slots
    end,
    AddItem=function(_,src,name,count,metadata)
        if onAdd then onAdd(src,name,count,metadata) end
        if name==failAdd then return false end
        if name==throwAdd then error('test uncertain delivery') end
        local p=inventory[data[src].citizenid] local slot=#p.items+1
        p.items[slot]={name=name,count=count,metadata=copy(metadata),slot=slot}
        p.weight=p.weight+definitions[name].weight*count
        additions[#additions+1]={owner=data[src].citizenid,name=name,count=count,metadata=copy(metadata)}
        return true,p.items[slot]
    end,
}
exports={ox_inventory=inv,qbx_core={GetPlayer=function(_,src) return data[src] and {PlayerData=data[src]} end}}
local prefix='ptech_omnite_toolbox:treasure:'
local function call(action,src,...) return callbacks[prefix..action](src,...) end
local function contents(id,items) stashes[prefix..'rewards:'..id]=copy(items) end
local function set()
    return {{name='water',count=2,slot=1,weight=200,metadata={label='Special water'}},{name='bandage',count=3,slot=2,weight=150,metadata={}}}
end
local npc1,npc2
function runTreasureSpecs()
    assert(not call('list',1,true).ok) init()
    local input={name='Treasure',model='s_m_m_highsec_01',enabled=true}
    assert(not call('save',2,input).ok,'non-admin cannot place')
    tool=false assert(not call('save',1,input).ok) tool=true
    input.model='bad model' assert(not call('save',1,input).ok) input.model='s_m_m_highsec_01'
    failDB=true assert(not call('save',1,input).ok) failDB=false
    local saved=call('save',1,input) assert(saved.ok) npc1=saved.id
    assert(call('list',2).points[npc1] and not call('list',1,true).points[npc1].rewards)
    assert(not call('claim',2,npc1).ok and #additions==0,'empty rewards do not consume claim')
    contents(npc1,set())
    local template=copy(stashes[prefix..'rewards:'..npc1])
    assert(call('stash',1,npc1).ok and not call('stash',2,npc1).ok)
    assert(hooks.openInventory({source=2,inventoryId=prefix..'rewards:'..npc1})==false)
    assert(hooks.swapItems({source=2,fromInventory='player',toInventory=prefix..'rewards:'..npc1})==false)
    positions[2].x=100 assert(not call('claim',2,npc1).ok) positions[2].x=1
    buckets[2]=1 assert(not call('claim',2,npc1).ok and not call('list',2).points[npc1]) buckets[2]=0
    inventory.two.maxWeight=300 assert(not call('claim',2,npc1).ok and #additions==0,'combined reward weight is checked') inventory.two.maxWeight=20000
    inventory.two.slots=1 assert(not call('claim',2,npc1).ok and #additions==0,'combined slot requirement is checked') inventory.two.slots=20
    onAdd=function()
        assert(not call('claim',2,npc1).ok,'simultaneous claim is blocked')
        assert(hooks.swapItems({source=1,fromInventory='player',toInventory=prefix..'rewards:'..npc1})==false,'template is protected while snapshot is being delivered')
    end
    assert(call('claim',2,npc1).ok and #additions==2) onAdd=nil
    assert(additions[1].count==2 and additions[1].metadata.label=='Special water' and additions[2].count==3)
    assert(stashes[prefix..'rewards:'..npc1][1].count==template[1].count,'template is not consumed')
    assert(not call('claim',2,npc1).ok and #additions==2,'same character cannot claim twice')
    assert(call('claim',1,npc1).ok and #additions==4,'different character gets its own once-only reward')
    input.id,input.revision=npc1,1 input.name='Renamed'
    assert(call('save',1,input).ok and not call('claim',2,npc1).ok,'editing does not reset claims')
    assert(not call('save',1,input).ok,'stale edit rejected')
    input.id,input.revision=nil,nil
    saved=call('save',1,input) assert(saved.ok) npc2=saved.id contents(npc2,set())
    failAdd='bandage'
    assert(not call('claim',2,npc2).ok and #additions==5,'partial failure preserves already delivered prefix')
    failAdd=nil
    assert(call('claim',2,npc2).ok and #additions==6 and additions[6].name=='bandage','retry only delivers remaining items')
    onGiving=function() data[1].citizenid='changed' end
    assert(not call('claim',1,npc2).ok and #additions==6,'identity change during DB wait is detected') data[1].citizenid='one'
    failCommit=true
    assert(not call('claim',1,npc2).ok and #additions==7,'grant followed by DB error is uncertain')
    assert(not call('claim',1,npc2).ok and #additions==7,'uncertain grant is not automatically repeated')
    local review=call('reviews',1,npc2) assert(review.ok and #review.claims==1)
    assert(not call('resolve',2,npc2,'one',1,true).ok,'review is admin only')
    assert(call('resolve',1,npc2,'one',1,true).ok,'confirmed delivered item advances claim')
    assert(call('claim',1,npc2).ok and #additions==8 and additions[8].name=='bandage')
    assert(not call('delete',1,npc2,1).ok,'nonempty reward stash prevents loss on deletion')
    contents(npc2,{}) assert(call('delete',1,npc2,1).ok)
    assert(db.claims[key(npc2,'one')].status=='paid','deletion retains claim history')
    -- 無確定の配布例外は管理者が未配布と確認した場合だけ再試行します。
    saved=call('save',1,input) assert(saved.ok) local npc3=saved.id contents(npc3,{set()[1]})
    local beforeFull=#additions
    onGiving=function() inventory.two.slots=0 end
    assert(not call('claim',2,npc3).ok and #additions==beforeFull and db.claims[key(npc3,'two')].status=='ready','inventory filled during DB wait does not cause partial AddItem success')
    inventory.two.slots=20
    throwAdd='water' assert(not call('claim',2,npc3).ok) throwAdd=nil
    local before=#additions assert(not call('claim',2,npc3).ok and #additions==before)
    assert(call('resolve',1,npc3,'two',1,false).ok)
    assert(call('claim',2,npc3).ok,'admin retry resolution unlocks the single pending item')
end
function runTreasureReloadSpecs()
    init()
    assert(call('list',1,true).points[npc1].name=='Renamed','NPC config is restored')
    local before=#additions
    assert(not call('claim',2,npc1).ok and #additions==before,'paid claim survives resource restart')
    assert(not call('list',1).points[npc2],'deleted NPC stays deleted')
end
