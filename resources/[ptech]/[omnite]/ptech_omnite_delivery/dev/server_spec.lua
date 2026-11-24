local callbacks, events, players, inventories, balances, locations = {}, {}, {}, {}, {}, {}
local money, coords, buckets = {}, {}, {}
local failAdd, failCredit, denyMoney, onCredit
local now = 100000
os.time = function() return now end
local saved = {}
json = {encode=function(value) saved[#saved+1]=value return 'saved'..#saved end,decode=function() return {} end}
lib = {callback={register=function(name,fn) callbacks[name]=fn end}}
exports = {
    qbx_core={GetPlayer=function(_,src) return players[src] end},
    ox_inventory={
        GetItemCount=function() return 1 end,
        Items=function() return {} end,
        CanCarryItem=function() return not failAdd end,
        AddItem=function(_,src,item,count,metadata)
            if failAdd then return false end
            local key = metadata and metadata.delivery or item
            inventories[src][key]=(inventories[src][key] or 0)+count
            return true
        end,
        RemoveItem=function(_,src,item,count,metadata,slot,ignoreTotal,strict)
            assert(strict==false,'metadata must permit box description')
            local key = metadata.delivery
            if (inventories[src][key] or 0)<count then return false end
            inventories[src][key]=inventories[src][key]-count
            return true
        end,
    },
}
MySQL = {
    ready=function(fn) fn() end,
    query={await=function(sql,args)
        if sql:find('SELECT %*') then return {} end
        if sql:find('INSERT INTO ptech_omnite_delivery_accounts') then
            if failCredit then error('database unavailable') end
            if onCredit then local fn=onCredit onCredit=nil fn() end
            balances[args[1]]=(balances[args[1]] or 0)+args[2]
        end
        if sql:find('INSERT INTO ptech_omnite_delivery_locations') then locations[args[1]]=args[2] end
        return {}
    end},
    scalar={await=function(_,args) return balances[args[1]] end},
    update={await=function(sql,args)
        local amount,job = args[1],args[2]
        if sql:find('points = points %-') then
            if (balances[job] or 0)<amount then return 0 end
            balances[job]=balances[job]-amount
        else balances[job]=(balances[job] or 0)+amount end
        return 1
    end},
}
function IsPlayerAceAllowed(src) return src==1 end
function GetPlayerPed(src) return src end
function GetPlayerRoutingBucket(src) return buckets[src] or 0 end
function GetEntityCoords(src) return coords[src] end
function GetPlayers() return {} end
function TriggerClientEvent() end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread() end
local function invoke(src,name,...) return callbacks['ptech_omnite_delivery:'..name](src,...) end
local function makePlayer(src,job,boss)
    inventories[src],money[src],coords[src] = {},0,{x=0,y=0,z=0}
    players[src]={PlayerData={citizenid='citizen'..src,job={name=job,isboss=boss,onduty=true}},Functions={
        AddMoney=function(_,amount) if denyMoney then return false end money[src]=money[src]+amount return true end,
        RemoveMoney=function(_,amount) if money[src]<amount then return false end money[src]=money[src]-amount return true end,
    }}
end
local function point(id,kind,job,x)
    return {id=id,label=id,kind=kind,job=job,reward=100,points=2,coords={x=x or 0,y=0,z=0},heading=0,bucket=0}
end
function runSpecs()
    makePlayer(1,'diner',true) makePlayer(2,'diner',false) makePlayer(3,'other',false)
    assert(invoke(1,'manage','save',point('shop','shop','diner')).ok)
    assert(invoke(1,'manage','save',point('pickup','pickup',nil,10)).ok)
    assert(invoke(1,'manage','save',point('market','market')).ok)
    assert(not invoke(2,'manage','save',point('unauthorized','shop','diner')).ok)
    assert(not invoke(3,'work','start','shop').ok,'other job cannot start')
    buckets[2]=1 assert(not invoke(2,'work','start','shop').ok) buckets[2]=0
    coords[2].x=30 assert(not invoke(2,'work','start','shop').ok) coords[2].x=0
    local m=invoke(2,'work','start','shop').mission
    assert(m and m.pickup=='pickup')
    assert(not invoke(2,'work','start','shop').ok,'one active delivery')
    assert(not invoke(2,'work','pickup','pickup').ok,'distance checked at pickup')
    assert(not invoke(2,'work','deliver','shop').ok,'must collect first')
    coords[2].x=10 failAdd=true
    assert(not invoke(2,'work','pickup','pickup').ok,'full inventory does not mark collected')
    failAdd=false assert(invoke(2,'work','pickup','pickup').ok)
    assert(not invoke(2,'work','pickup','pickup').ok,'duplicate collection rejected')
    coords[2].x=0 failCredit=true
    assert(not invoke(2,'work','deliver','shop').ok,'DB failure returns box')
    assert(inventories[2][m.token]==1 and money[2]==0)
    failCredit=false denyMoney=true
    assert(not invoke(2,'work','deliver','shop').ok,'payout failure compensates')
    assert(inventories[2][m.token]==1 and balances.diner==0)
    denyMoney=false
    onCredit=function() assert(not invoke(2,'work','deliver','shop').ok,'nested duplicate blocked while DB yields') end
    assert(invoke(2,'work','deliver','shop').ok)
    assert(money[2]==100 and balances.diner==2)
    assert(not invoke(2,'work','deliver','shop').ok and balances.diner==2,'no second reward')
    assert(invoke(1,'shop','shop').points==2,'shared points across employees')
    assert(not invoke(3,'buy','shop','normal',1).ok)
    assert(not invoke(2,'buy','shop','normal',-1).ok)
    assert(not invoke(2,'buy','shop','normal',0/0).ok)
    assert(not invoke(2,'buy','shop','normal',3).ok)
    failAdd=true assert(not invoke(2,'buy','shop','normal',1).ok and balances.diner==2)
    failAdd=false
    -- Fail after CanCarryItem succeeds to verify economic compensation.
    local canCarry=exports.ox_inventory.CanCarryItem
    exports.ox_inventory.CanCarryItem=function() failAdd=true return true end
    assert(not invoke(2,'buy','shop','normal',1).ok and balances.diner==2,'failed grant refunds points')
    failAdd=false exports.ox_inventory.CanCarryItem=canCarry
    assert(invoke(2,'buy','shop','normal',2).ok and balances.diner==0)
    assert(inventories[2].pomnite_food_supply==2)
    money[2]=50000 assert(not invoke(2,'buy','market','normal',1).ok,'non boss cannot pay cash')
    money[1]=50000 assert(invoke(1,'buy','market','normal',2).ok and money[1]==35000)
    assert(inventories[1].pomnite_food_supply==2)
    now=now+61
    coords[2].x=0 assert(invoke(2,'work','start','shop').ok)
    coords[2].x=10 assert(invoke(2,'work','pickup','pickup').ok)
    players[2].PlayerData.job.name='other'
    coords[2].x=0 assert(not invoke(2,'work','deliver','shop').ok,'job change invalidates delivery')
    assert(money[2]==50000 and balances.diner==0)
    players[2].PlayerData.job.name='diner'
    now=now+61
    local expired=invoke(2,'work','start','shop').mission
    now=now+Config.missionSeconds+1
    assert(not invoke(2,'work','deliver','shop').ok,'expired delivery rejected')
    assert(invoke(1,'manage','export').ok)
    local invalid=point('bad','shop','diner') invalid.coords.x=0/0
    assert(not invoke(1,'manage','save',invalid).ok)
end
