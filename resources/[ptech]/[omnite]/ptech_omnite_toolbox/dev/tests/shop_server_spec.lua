local callbacks,events,hooks={}, {}, {}
local serverThreads,serverPlayers,serverBucket,shopStates={},{},0,{}
function CreateThread(fn) serverThreads[#serverThreads+1]=coroutine.create(fn) end
function Wait() coroutine.yield() end
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
function GetPlayerRoutingBucket() return serverBucket end
function GetPlayers() return serverPlayers end
function TriggerClientEvent(name,src,state) if name=='ptech_omnite_shops:state' then shopStates[#shopStates+1]=state end end
function AddEventHandler(name,fn) events[name]=fn end
function GetCurrentResourceName() return 'ptech_omnite_toolbox' end
function vec3(x,y,z) return {x=x,y=y,z=z} end
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
exports={qbx_core={GetJobs=function() return {diner={label='Diner'},citizen={label='Citizen'}} end,GetPlayer=function(_,src) return {PlayerData={job=roles[src]}} end},ox_inventory={
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
    assert(registered[open.shop].randomprices==false,'toolbox shops disable price randomisation')
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
    -- Cross-resource calls copy payload tables; hook mutations do not reach ox's post event.
    purchase.omniteSale=nil
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
    config.revision=shop.revision config.purchaseJob=nil config.stockJob=nil
    assert(not invoke(2,'inventory','shop1','stock').ok,'unlimited catalogue is admin managed')
    config.finite=true
    config.purchaseJobs={'diner','citizen'} config.stockJobs={'diner','citizen'}
    assert(invoke(1,'save',config).ok)
    assert(invoke(2,'open','shop1').ok and invoke(4,'open','shop1').ok,'both selected purchase jobs may buy')
    assert(not invoke(1,'open','shop1').ok,'unlisted job cannot buy even as admin')
    assert(invoke(4,'inventory','shop1','stock').ok,'second stock job may manage inventory')
    assert(not invoke(4,'inventory','shop1','sales').ok,'second stock job employee cannot collect sales')
    roles[4].isboss=true
    assert(invoke(4,'inventory','shop1','sales').ok,'second stock job boss may collect sales')
    shop=invoke(1,'list').shops.shop1 config.revision=shop.revision
    config.purchaseGrades={diner=2,citizen=4}
    assert(invoke(1,'save',config).ok)
    roles[2].grade={level=1} roles[4].grade={level=3}
    assert(not invoke(2,'open','shop1').ok and not invoke(4,'open','shop1').ok,'each job has its own minimum grade')
    roles[2].grade={level=2} roles[4].grade=4
    assert(invoke(2,'open','shop1').ok and invoke(4,'open','shop1').ok,'minimum grade is inclusive for table and numeric grades')
    roles[4].grade=5
    assert(invoke(4,'open','shop1').ok,'grades above the minimum may buy')
    assert(invoke(4,'inventory','shop1','stock').ok,'purchase grade does not change stock permissions')
    roles[2].grade={level=1}
    assert(hooks.openShop({source=2,shopType=purchase.shopType})==false,'direct shop open checks grade')
    assert(hooks.buyItem(purchase)==false,'grade downgrade blocks buying from an already opened shop')
    roles[2].grade={level=2}
    shop=invoke(1,'list').shops.shop1 config.revision=shop.revision
    config.purchaseGrades={diner=-1}
    assert(not invoke(1,'save',config).ok,'negative grades are rejected')
    config.purchaseGrades={diner=1.5}
    assert(not invoke(1,'save',config).ok,'fractional grades are rejected')
    config.purchaseGrades='invalid'
    assert(not invoke(1,'save',config).ok,'malformed grades are rejected')
    config.purchaseGrades={diner=2,citizen=4}
    config.stockJobs={'diner',false}
    assert(not invoke(1,'save',config).ok,'malformed job lists are rejected')
    config.stockJobs={} config.purchaseJobs={}
    assert(invoke(1,'save',config).ok)
    assert(invoke(4,'open','shop1').ok,'empty purchase list allows all jobs')
    assert(not invoke(4,'inventory','shop1','stock').ok,'empty stock list allows only admins')
    assert(invoke(1,'inventory','shop1','stock').ok)
    shop=invoke(1,'list').shops.shop1
    assert(invoke(1,'delete','shop1',shop.revision).ok)
    assert(#drops==2,'deletion drops uncarryable templates and proceeds')
    assert(drops[1][1][2]==2 and drops[2][1][2]==50,'deletion returns actual count, including unlimited templates')
    assert(next(invoke(1,'list').shops)==nil)
    assert(invoke(1,'save',{name='Sparse shop',coords={x=0,y=0,z=0},heading=0,finite=true,model=false}).ok)
    local sparseStock='ptech_omnite_shops:stock:shop2'
    inventories[sparseStock][2]={slot=2,name='water',count=2,metadata={quality=1}}
    inventories[sparseStock][190]={slot=190,name='water',count=4,metadata={quality=2}}
    inventories[sparseStock][500]={slot=500,name='bread',count=6,metadata={}}
    for _,slot in ipairs({2,190,500}) do
        local listing=invoke(1,'products','shop2')
        assert(#listing.products==3,'all sparse stock slots appear in settings')
        for _,entry in ipairs(listing.products) do
            if entry.slot==slot then assert(invoke(1,'product','shop2',{slot=slot,key=entry.key,revision=listing.revision,price=slot*100,enabled=true}).ok) end
        end
    end
    local vaultShop=invoke(1,'list').shops.shop2
    local vaultInput={revision=vaultShop.revision,inherit=false,jobs={'diner','citizen'},grades={diner=2,citizen=5},bossOnly=false}
    assert(not invoke(2,'vaultAccess','shop2',vaultInput).ok,'only managers configure vault access')
    assert(invoke(1,'vaultAccess','shop2',vaultInput).ok)
    assert(invoke(2,'inventory','shop2','sales').ok,'configured employee grade may open vault without boss status')
    assert(invoke(4,'inventory','shop2','sales').ok,'second configured job grade may open vault')
    assert(not invoke(3,'inventory','shop2','sales').ok,'boss below configured minimum cannot open vault')
    roles[2].grade={level=1}
    local vaultId='ptech_omnite_shops:sales:shop2'
    assert(not invoke(2,'inventory','shop2','sales').ok,'grade below minimum cannot open vault')
    assert(hooks.openInventory({source=2,inventoryId=vaultId})==false,'direct vault opens recheck custom permission')
    assert(hooks.swapItems({source=2,fromInventory=vaultId,toInventory=2,fromSlot={name='money'}})==false,'direct money transfer rechecks custom permission')
    roles[2].grade={level=2}
    vaultShop=invoke(1,'list').shops.shop2
    local update={id=vaultShop.id,revision=vaultShop.revision,name=vaultShop.name,model=false,finite=true,coords=vaultShop.coords,heading=vaultShop.heading}
    assert(invoke(1,'save',update).ok)
    assert(invoke(2,'inventory','shop2','sales').ok,'unrelated shop edits preserve vault permissions')
    vaultShop=invoke(1,'list').shops.shop2 vaultInput.revision=vaultShop.revision vaultInput.bossOnly=true
    assert(invoke(1,'vaultAccess','shop2',vaultInput).ok)
    assert(not invoke(2,'inventory','shop2','sales').ok,'optional boss restriction excludes employees')
    assert(invoke(4,'inventory','shop2','sales').ok,'configured boss above minimum may open vault')
    vaultShop=invoke(1,'list').shops.shop2 vaultInput.revision=vaultShop.revision
    vaultInput.grades={diner=-1}
    assert(not invoke(1,'vaultAccess','shop2',vaultInput).ok,'invalid vault grade is rejected')
    vaultInput.grades={unlisted=1}
    assert(not invoke(1,'vaultAccess','shop2',vaultInput).ok,'unselected job grade is rejected')
    vaultInput.jobs={} vaultInput.grades={} vaultInput.bossOnly=false
    assert(invoke(1,'vaultAccess','shop2',vaultInput).ok)
    assert(not invoke(4,'inventory','shop2','sales').ok,'empty explicit ACL never opens vault to everyone')
    vaultShop=invoke(1,'list').shops.shop2
    assert(invoke(1,'vaultAccess','shop2',{revision=vaultShop.revision,inherit=true}).ok)
    assert(not invoke(4,'inventory','shop2','sales').ok,'legacy mode follows stock jobs, not previous custom ACL')
    local listed=invoke(4,'open','shop2')
    local offer=registered[listed.shop].inventory
    assert(#offer==3,'all enabled sparse products appear in purchase list')
    assert(offer[1].price==200 and offer[2].price==19000 and offer[3].price==50000,'purchase list uses each configured price in layout order')
    assert(offer[1].metadata.quality==1 and offer[2].metadata.quality==2,'metadata variants remain separate products')
    local before=invoke(1,'list').shops.shop2
    local keep={id='shop2',revision=before.revision,name=before.name,model=false,finite=true,
        relocate=false,coords={x=100,y=100,z=100},heading=270,coordinateMode='origin'}
    assert(invoke(1,'save',keep).ok)
    local preserved=invoke(1,'list').shops.shop2
    assert(preserved.coords.z==before.coords.z and preserved.heading==before.heading and preserved.coordinateMode==before.coordinateMode,'ordinary edits preserve original position and coordinate mode')
    keep.revision=preserved.revision keep.relocate=true keep.coords={x=0,y=0,z=1} keep.heading=90
    assert(invoke(1,'save',keep).ok)
    local moved=invoke(1,'list').shops.shop2
    assert(moved.coords.z==1 and moved.heading==90 and moved.coordinateMode=='origin','explicit relocation stores exact origin coordinates')
    keep.revision=moved.revision keep.relocate=false keep.coords={x=100,y=100,z=-500} keep.coordinateMode=nil keep.heading=180
    assert(invoke(1,'save',keep).ok)
    local stable=invoke(1,'list').shops.shop2
    assert(stable.coords.z==1 and stable.heading==90 and stable.coordinateMode=='origin','repeated settings edits do not shift the saved origin')
    serverPlayers={'1'}
    assert(coroutine.resume(serverThreads[1])) assert(coroutine.resume(serverThreads[1]))
    assert(shopStates[#shopStates].shop2,'server sends state on initial bucket discovery')
    serverBucket=1 assert(coroutine.resume(serverThreads[1]))
    assert(next(shopStates[#shopStates])==nil,'other instance removes old shop state')
    serverBucket=0 assert(coroutine.resume(serverThreads[1]))
    assert(shopStates[#shopStates].shop2,'return from login instance restores shops without a job update')
end
