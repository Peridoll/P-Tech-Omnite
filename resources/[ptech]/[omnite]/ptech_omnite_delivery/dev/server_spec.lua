local callbacks, events, players, inventories, balances, locations = {}, {}, {}, {}, {}, {}
local money, coords, buckets = {}, {}, {}
local failAdd, failCredit, denyMoney, onCredit
local now = 100000
local shops, hooks = {}, {}
os.time = function() return now end
local saved = {}
local catalogRow,failCatalog
json = {encode=function(value) saved[#saved+1]=value return 'saved'..#saved end,decode=function(value) return saved[tonumber(value:match('^saved(%d+)$'))] or {} end}
lib = {callback={register=function(name,fn) callbacks[name]=fn end}}
exports = {
    qbx_core={GetPlayer=function(_,src) return players[src] end},
    ox_inventory={
        RegisterShop=function(_,name,properties) shops[name]=properties end,
        registerHook=function(_,name,fn,options)
            assert(options.inventoryFilter[1]=='^ptech_omnite_delivery_market_')
            hooks[name]=fn
        end,
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
        if sql:find('SELECT %* FROM ptech_omnite_delivery_catalog') then return catalogRow and {catalogRow} or {} end
        if sql:find('INSERT INTO ptech_omnite_delivery_catalog') then catalogRow={payload=args[1],revision=1} end
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
        if sql:find('UPDATE ptech_omnite_delivery_catalog') then
            if failCatalog then error('catalog database unavailable') end
            if args[2]~=catalogRow.revision then return 0 end
            catalogRow={payload=args[1],revision=catalogRow.revision+1}
            return 1
        end
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
local inVehicle=false
function GetVehiclePedIsIn() return inVehicle and 1 or 0 end
function GetPlayerRoutingBucket(src) return buckets[src] or 0 end
function GetEntityCoords(src) return coords[src] end
function GetPlayers() return {} end
function TriggerClientEvent() end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread() end
function GetCurrentResourceName() return 'ptech_omnite_delivery' end
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
    coords[2].x=10
    inVehicle=true assert(not invoke(2,'work','pickup','pickup').ok,'cannot handover from car') inVehicle=false
    failAdd=true
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
    money[2]=50000 assert(not invoke(2,'market','market').ok,'non boss cannot open market')
    assert(not invoke(1,'buy','market','normal',1).ok,'old market callback cannot bypass ox shop')
    local market=invoke(1,'market','market')
    assert(market.ok and market.shopType=='ptech_omnite_delivery_market_market')
    local registered=shops[market.shopType]
    assert(registered and #registered.inventory==6,'ox shop contains all six supplies')
    local prices={pomnite_food_supply=7500,pomnite_premium_supply=12500,pomnite_sweet_supply=12500,
        pomnite_adult_supply=12500,pomnite_tea_leaf=7500,pomnite_tobacco_leaf=7500}
    for _,item in ipairs(registered.inventory) do assert(item.price==prices[item.name]) end
    local open={source=1,shopType=market.shopType,items={{name='pomnite_food_supply',price=9000}}}
    assert(hooks.openShop(open)~=false and open.items[1].price==7500,'fixed prices override ox randomization')
    open.source=2 assert(hooks.openShop(open)==false,'direct ox opens require boss')
    open.source=1 coords[1].x=20 assert(hooks.openShop(open)==false,'direct ox opens require proximity') coords[1].x=0
    buckets[1]=1 assert(not invoke(1,'market','market').ok) buckets[1]=0
    local purchase={source=1,shopType=market.shopType,itemName='pomnite_food_supply',count=2,price=7500,totalPrice=15000,currency='money'}
    assert(hooks.buyItem(purchase)~=false)
    purchase.source=2 assert(hooks.buyItem(purchase)==false,'purchase rechecks boss') purchase.source=1
    coords[1].x=20 assert(hooks.buyItem(purchase)==false,'purchase rechecks distance') coords[1].x=0
    players[1].PlayerData.job.name='other' assert(hooks.buyItem(purchase)==false,'only registered shop bosses') players[1].PlayerData.job.name='diner'
    purchase.count=101 assert(hooks.buyItem(purchase)==false) purchase.count=2
    purchase.price=1 assert(hooks.buyItem(purchase)==false) purchase.price=7500
    purchase.itemName='pomnite_delivery_box' assert(hooks.buyItem(purchase)==false) purchase.itemName='pomnite_food_supply'
    assert(invoke(1,'manage','save',point('market','market',nil,20)).ok)
    assert(hooks.buyItem(purchase)==false,'moving market immediately rejects old location')
    assert(invoke(1,'manage','save',point('market','market')).ok)
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
    assert(invoke(1,'manage','save',point('pickup2','pickup',nil,20)).ok)
    buckets[1]=1
    assert(invoke(1,'manage','save',point('otherbucket','pickup',nil,30)).ok)
    buckets[1]=0
    local originalRandom=math.random
    local selected={}
    for index=1,2 do
        math.random=function(count) assert(count==2,'random pool excludes other bucket') return index end
        now=now+61
        local chosen=invoke(2,'work','start','shop').mission
        assert(chosen and (chosen.pickup=='pickup' or chosen.pickup=='pickup2'))
        selected[chosen.pickup]=true
        assert(invoke(2,'work','cancel','shop').ok)
    end
    math.random=originalRandom
    assert(selected.pickup and selected.pickup2,'both registered destinations can be selected')
    assert(invoke(1,'manage','delete','market').ok)
    assert(#shops[market.shopType].inventory==0 and hooks.buyItem(purchase)==false,'deleted shop disabled even for open inventory')
    assert(invoke(1,'manage','save',point('market','market')).ok)
    local catalog=invoke(1,'manage','products')
    assert(catalog.ok and #catalog.products==6,'manager reads initial catalog')
    assert(not invoke(2,'manage','products').ok,'employee cannot edit catalog')
    local product={id='normal',label='Updated food',item='pomnite_food_supply',cash=9000,points=2}
    assert(invoke(1,'manage','saveProduct',{revision=catalog.revision,product=product}).ok)
    assert(shops[market.shopType].inventory[1].price==9000,'price change immediately registers shop')
    assert(hooks.buyItem(purchase)==false,'previous price in already open shop is rejected')
    assert(invoke(1,'shop','shop').products[1].points==2,'point purchase UI receives live catalog')
    assert(not invoke(1,'manage','saveProduct',{revision=catalog.revision,product=product}).ok,'stale edits rejected')
    catalog=invoke(1,'manage','products')
    product={id='extra',label='Extra',item='pomnite_extra',cash=100}
    failCatalog=true
    assert(not invoke(1,'manage','saveProduct',{revision=catalog.revision,product=product}).ok)
    failCatalog=false
    assert(#invoke(1,'manage','products').products==6,'DB failure preserves live catalog')
    product.cash=-1
    assert(not invoke(1,'manage','saveProduct',{revision=catalog.revision,product=product}).ok,'negative price rejected')
    product.cash=100 product.item='pomnite_food_supply'
    assert(not invoke(1,'manage','saveProduct',{revision=catalog.revision,product=product}).ok,'duplicate item rejected')
    product.item='pomnite_extra'
    assert(invoke(1,'manage','saveProduct',{revision=catalog.revision,product=product}).ok,'new item added')
    catalog=invoke(1,'manage','products')
    assert(#catalog.products==7)
    assert(invoke(1,'manage','deleteProduct',{revision=catalog.revision,id='extra'}).ok,'item deleted')
    assert(#shops[market.shopType].inventory==6,'shop updated after deletion')
    assert(catalogRow and #json.decode(catalogRow.payload)==6,'catalog stored in DB')
    events.onResourceStop('ptech_omnite_delivery')
    assert(#shops[market.shopType].inventory==0,'stopped resource empties ox shops')
end

function verifyCatalogReload()
    local result=invoke(1,'manage','products')
    assert(result.ok and #result.products==6 and result.products[1].cash==9000 and result.products[1].points==2,
        'saved catalog restores after resource restart instead of Config defaults')
end
