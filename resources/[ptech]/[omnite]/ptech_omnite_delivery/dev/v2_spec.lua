local callbacks,events,tasks,players,items,positions,buckets,accounts,runs={},{},{},{},{},{},{},{},{}
local clock=100000
os.time=function() return clock end
local saved,catalogRow={},nil
json={encode=function(value) saved[#saved+1]=value return tostring(#saved) end,decode=function(value) return saved[tonumber(value)] end}
local sequence=0
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
function IsPlayerAceAllowed(src) return src==1 end
function GetVehiclePedIsIn() return 0 end
function GetPlayerPed(src) return players[src] and src or 0 end
function GetEntityCoords(src) return positions[src] end
function GetPlayerRoutingBucket(src) return buckets[src] or 0 end
function GetPlayers() return {} end
function TriggerClientEvent() end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread(fn) tasks[#tasks+1]=fn end
function GetCurrentResourceName() return 'ptech_omnite_delivery' end
local failAdd=false
exports={qbx_core={GetPlayer=function(_,src) return players[src] end},ox_inventory={
    GetItemCount=function(_,src,item) if item=='pomnite_toolbox' then return 1 end return items[src][item] or 0 end,
    Items=function(_,name) return name and {label=name} or {pomnite_food_supply={label='Food'}} end,
    CanCarryItem=function() return not failAdd end,
    AddItem=function(_,src,item,count,metadata)
        if failAdd then return false end
        local key=metadata and metadata.delivery or item items[src][key]=(items[src][key] or 0)+count return true
    end,
    RemoveItem=function(_,src,item,count,metadata)
        local key=metadata and metadata.delivery or item
        if (items[src][key] or 0)<count then return false end items[src][key]=items[src][key]-count return true
    end,
}}
MySQL={ready=function(fn) fn() end,query={await=function(sql,args)
    if sql:find('SELECT %* FROM ptech_omnite_delivery_catalog') then return catalogRow and {catalogRow} or {} end
    if sql:find('INSERT INTO ptech_omnite_delivery_catalog') then catalogRow={payload=args[1],revision=1} end
    return {}
end},scalar={await=function(sql,args)
    if sql:find('UUID') then sequence=sequence+1 return 'id_'..sequence end
    return 0
end},update={await=function(sql,args)
    if sql:find('delivery_catalog') then if args[2]~=catalogRow.revision then return 0 end catalogRow={payload=args[1],revision=catalogRow.revision+1} return 1 end
    return 1
end}}
DeliveryFinance={ready=true}
local F=DeliveryFinance
function F.register(id) accounts[id]=accounts[id] or {points=0,vault=0} end
function F.account(id) return accounts[id] or {points=0,vault=0} end
function F.used(id) for _,m in pairs(runs) do if (m.shop==id or m.pickup==id) and (m.status=='active' or m.status=='paying') then return true end end return false end
function F.hasRun(owner) for _,m in pairs(runs) do if m.owner==owner and (m.status=='active' or m.status=='paying') then return true end end return false end
function F.reserve(m)
    local a=accounts[m.shop] if a.vault<m.reward then return false end
    a.vault=a.vault-m.reward runs[m.token]={shop=m.shop,pickup=m.pickup,reward=m.reward,points=m.points,owner=m.owner,status='active'} return true
end
function F.refund(m) local r=runs[m.token] if r and r.status=='active' then accounts[m.shop].vault=accounts[m.shop].vault+r.reward r.status='refunded' end end
function F.beginPay(m) local r=runs[m.token] if r.status~='active' then return false end r.status='paying' return true end
function F.payFailed(m) runs[m.token].status='active' end
function F.complete(m) local r=runs[m.token] if r.status=='paying' then accounts[m.shop].points=accounts[m.shop].points+r.points r.status='paid' end end
function F.buy(id,cost) local a=accounts[id] if a.points<cost then return false end a.points=a.points-cost return true end
function F.refundPoints(id,cost) accounts[id].points=accounts[id].points+cost end
function F.wallet(src,point,action,amount)
    local a=accounts[point.id]
    if action=='deposit' then if (items[src].money or 0)<amount then return false,'cash' end items[src].money=items[src].money-amount a.vault=a.vault+amount
    else if a.vault<amount then return false,'balance' end a.vault=a.vault-amount items[src].money=(items[src].money or 0)+amount end
    return true
end
function F.reviews() return {runs={},transfers={}} end
local function invoke(src,action,...) return callbacks['ptech_omnite_delivery:'..action](src,...) end
local function point(id,kind,x)
    return {id=id,label=id,kind=kind,job=kind=='shop' and 'diner' or nil,reward=400000,points=600,
        coords={x=x or 0,y=0,z=0},heading=0,model='s_m_m_dockwork_01'}
end
function runSpecs()
    for src=1,3 do
        players[src]={PlayerData={citizenid='owner'..src,job={name=src==3 and 'other' or 'diner',isboss=src==1,onduty=false}}}
        items[src]={money=2000000} positions[src]={x=0,y=0,z=0}
    end
    assert(invoke(1,'manage','save',point('a','shop')).ok)
    assert(invoke(1,'manage','save',point('b','shop')).ok)
    assert(invoke(1,'manage','save',point('destination','pickup',10)).ok)
    assert(not invoke(2,'manage','save',point('bad','shop')).ok,'management is admin only')
    assert(not invoke(3,'work','start','a').ok,'other job cannot accept')
    assert(not invoke(2,'work','start','a').ok,'empty vault prevents acceptance')
    assert(not invoke(2,'vault','a','deposit',100).ok,'ordinary employee cannot deposit')
    assert(invoke(1,'vault','a','deposit',800000).ok)
    local astate=invoke(1,'shop','a') assert(astate.vault==800000,tostring(astate.vault)..' '..tostring(astate.message))
    local first=invoke(2,'work','start','a').mission
    assert(first and first.reward==400000,'off-duty employee can accept')
    assert(accounts.a.vault==400000,'reward reserved at acceptance')
    assert(not invoke(2,'work','start','b').ok,'one active delivery per employee')
    assert(not invoke(1,'manage','delete','destination').ok,'active destinations cannot be removed')
    positions[2].x=10 assert(invoke(2,'work','pickup','destination').ok)
    positions[2].x=0 assert(invoke(2,'work','deliver','a').ok)
    assert(items[2].money==2400000 and accounts.a.points==600 and accounts.b.points==0,'cash paid once, points belong to one store')
    assert(not invoke(2,'work','deliver','a').ok,'double delivery rejected')
    assert(invoke(2,'buy','a','normal',2).ok and accounts.a.points==594,'3 points per normal material')
    assert(not invoke(2,'buy','b','normal',1).ok,'other store cannot spend points')
    assert(invoke(1,'vault','a','reward',100000).ok,'boss controls future reward')
    clock=clock+61
    local second=invoke(2,'work','start','a').mission
    assert(second.reward==100000 and accounts.a.vault==300000)
    assert(invoke(1,'vault','a','reward',200000).ok)
    assert(second.reward==100000,'accepted reward stays fixed after boss changes price')
    assert(invoke(2,'work','cancel','a').ok and accounts.a.vault==400000,'cancel refunds original reservation')
    F.refund(second) assert(accounts.a.vault==400000,'repeat refund is idempotent')
    clock=clock+61
    local third=invoke(2,'work','start','a').mission
    source=2 events.playerDropped() tasks[#tasks]()
    assert(accounts.a.vault==400000 and runs[third.token].status=='refunded','logout refunds escrow')
    clock=clock+61
    local fourth=invoke(2,'work','start','a').mission
    clock=clock+Config.missionSeconds+1
    invoke(2,'state') assert(accounts.a.vault==400000 and runs[fourth.token].status=='refunded','expiration refunds escrow')
    local data=invoke(1,'manage','products')
    assert(invoke(1,'manage','saveProduct',{revision=data.revision,product={id='normal',item='pomnite_food_supply',label='Food',points=7}}).ok)
    assert(not invoke(1,'manage','saveProduct',{revision=data.revision,product={id='normal',item='pomnite_food_supply',label='Food',points=1}}).ok,'stale catalog updates rejected')
    assert(invoke(2,'shop','a').products[1].points==7,'employees see current exchange rates')
end
function verifyCatalogReload()
    local data=invoke(1,'manage','products') assert(data.ok and data.products[1].points==7,'catalog restored on reload')
end
