local callbacks,events,hooks={}, {}, {}
local positions={[1]={x=0,y=0,z=0},[2]={x=0,y=0,z=0},[3]={x=0,y=0,z=0},[4]={x=0,y=0,z=0}}
local roles={[1]={name='adminjob'},[2]={name='diner'},[3]={name='diner',isboss=true},[4]={name='citizen'}}
local inventories,registered,stashDefs={},{},{}
local saved={} local nextId=0 local drops={}
json={encode=function(value)
    if type(value)=='table' then saved[#saved+1]=value return 'table'..#saved end
    return tostring(value)
end,decode=function(value)
    local t=saved[tonumber(value:match('table(%d+)'))]
    local function copy(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
    return copy(t)
end}
function IsPlayerAceAllowed(src) return src==1 end
function GetPlayerPed(src) return src end
function GetEntityCoords(src) return positions[src] end
function GetPlayerRoutingBucket() return 0 end
function GetPlayers() return {} end
function TriggerClientEvent() end
function AddEventHandler(name,fn) events[name]=fn end
function GetCurrentResourceName() return 'ptech_omnite_toolbox' end
function vec3(x,y,z) return {x=x,y=y,z=z} end
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
exports={qbx_core={GetPlayer=function(_,src) return {PlayerData={job=roles[src]}} end},ox_inventory={
    GetItemCount=function() return 1 end,
    RegisterStash=function(_,id,label,slots,weight) stashDefs[id]={slots=slots,weight=weight} inventories[id]=inventories[id] or {} end,
    GetInventoryItems=function(_,id) return inventories[id] or {} end,
    GetSlot=function(_,id,slot) return inventories[id] and inventories[id][slot] end,
    RegisterShop=function(_,id,data) registered[id]=data end,
    registerHook=function(_,name,fn) hooks[name]=fn return 'post:'..name end,
    CanCarryItem=function() return true end,
    CanCarryAmount=function() return 0 end,
    RemoveItem=function(_,id,name,count,metadata,slot)
        if not slot then for n,item in pairs(inventories[id]) do if item.name==name then slot=n break end end end
        local item=inventories[id][slot]
        if not item or item.name~=name or item.count<count then return false end
        item.count=item.count-count if item.count==0 then inventories[id][slot]=nil end return true
    end,
    AddItem=function(_,id,name,count,metadata,slot)
        inventories[id]=inventories[id] or {}
        slot=slot or 1
        local item=inventories[id][slot]
        if item and item.name==name then item.count=item.count+count
        else inventories[id][slot]={name=name,count=count,metadata=metadata or {},slot=slot} end return true
    end,
    CustomDrop=function(_,label,items) drops[#drops+1]=items return 'drop'..#drops end,
}}
MySQL={ready=function(fn) fn() end,query={await=function() return {} end},scalar={await=function() nextId=nextId+1 return 'shop'..nextId end}}
local function invoke(src,action,...) return callbacks['ptech_omnite_shops:'..action](src,...) end
function runShopSpecs()
    local config={name='Shop',coords={x=0,y=0,z=0},heading=0,finite=true,model=false,stockJob='diner'}
    assert(not invoke(2,'save',config).ok,'employees cannot create shops')
    assert(invoke(1,'save',config).ok)
    local shop=invoke(1,'list').shops.shop1
    local stock='ptech_omnite_shops:stock:shop1'
    local sales='ptech_omnite_shops:sales:shop1'
    assert(stashDefs[stock].slots==500 and stashDefs[stock].weight==100000000,'large layout stash')
    inventories[stock][7]={slot=7,name='water',count=3,label='Water',metadata={label='Custom water',quality=5}}
    local details=invoke(1,'products','shop1')
    assert(details.products[1].enabled==false,'new products start disabled')
    local open=invoke(4,'open','shop1') assert(open.ok and #registered[open.shop].inventory==0,'disabled item is not offered')
    local item=details.products[1]
    assert(invoke(1,'product','shop1',{slot=7,key=item.key,price=25,enabled=true,revision=details.revision}).ok)
    open=invoke(4,'open','shop1')
    assert(registered[open.shop].inventory[1].metadata.quality==5,'metadata is retained in offer')
    assert(invoke(2,'inventory','shop1','stock').ok,'registered stock job can replenish')
    assert(not invoke(2,'inventory','shop1','sales').ok,'stock employee cannot withdraw proceeds')
    assert(invoke(3,'inventory','shop1','sales').ok,'boss of stock job can withdraw proceeds')
    assert(not invoke(4,'inventory','shop1','stock').ok,'customers cannot access stock')
    assert(hooks.openInventory({source=4,inventoryId=stock})==false,'direct inventory opens are checked')
    assert(hooks.swapItems({source=2,fromInventory=sales,toInventory=2,fromSlot={name='money'}})==false,'direct sales withdrawal is checked')
    assert(hooks.swapItems({source=3,fromInventory=3,toInventory=sales,fromSlot={name='water'}})==false,'sales inventory accepts only money')
    local purchase={source=4,shopType=open.shop,fromSlot={slot=1,metadata={label='Custom water',quality=5}},itemName='water',currency='money',count=1,price=25,totalPrice=25}
    purchase.itemName='bread' assert(hooks.buyItem(purchase)==false,'stale or mismatched item cannot consume another product') purchase.itemName='water'
    assert(hooks.buyItem(purchase)~=false,'valid cash purchase reserves stock')
    assert(inventories[stock][7].count==2)
    events['post:buyItem'](true,purchase)
    assert(inventories[sales][1].name=='money' and inventories[sales][1].count==25,'successful sale credits dedicated proceeds stash')
    invoke(4,'open','shop1')
    hooks.buyItem(purchase) events['post:buyItem'](false,purchase)
    assert(inventories[stock][7].count==2 and inventories[sales][1].count==25,'rejected purchase restores stock and does not credit money')
    local details2=invoke(1,'products','shop1')
    shop=invoke(1,'list').shops.shop1
    config.id=shop.id config.revision=shop.revision config.finite=false config.purchaseJob='diner'
    assert(invoke(1,'save',config).ok)
    assert(not invoke(4,'open','shop1').ok,'shop purchase job restriction')
    local unlimited=invoke(2,'open','shop1')
    assert(registered[unlimited.shop].inventory[1].count==nil,'unlimited offers have no quantity limit')
    purchase.source=2 purchase.shopType=unlimited.shop
    hooks.buyItem(purchase) events['post:buyItem'](true,purchase)
    assert(inventories[stock][7].count==2,'unlimited sale keeps physical template count')
    shop=invoke(1,'list').shops.shop1
    assert(invoke(1,'delete','shop1',shop.revision).ok)
    assert(#drops==2,'deletion drops uncarryable templates and proceeds')
    assert(drops[1][1][2]==2 and drops[2][1][2]==50,'deletion returns actual count, including unlimited templates')
    assert(next(invoke(1,'list').shops)==nil)
end
