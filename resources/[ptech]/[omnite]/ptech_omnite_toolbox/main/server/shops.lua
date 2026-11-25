local shops,locks,stashes,offers={},{},{},{}
local ready=false
local prefix='ptech_omnite_shops:'
local inv=exports.ox_inventory
local function fail(message) return {ok=false,message=message} end
local function admin(src) return IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god') or IsPlayerAceAllowed(src,'omnite.shops.admin') end
local function manager(src) return admin(src) and (inv:GetItemCount(src,'pomnite_toolbox') or 0)>0 end
local function role(src) local p=exports.qbx_core:GetPlayer(src) return p and p.PlayerData.job end
local function near(src,p)
    if GetPlayerPed(src)==0 or GetPlayerRoutingBucket(src)~=p.bucket then return false end
    local c=GetEntityCoords(GetPlayerPed(src))
    return (c.x-p.coords.x)^2+(c.y-p.coords.y)^2+(c.z-p.coords.z)^2<=9
end
local function allowed(src,p,mode)
    if not ready or not p or not near(src,p) then return false end
    local job=role(src)
    if mode=='sales' then return job and p.stockJob and job.name==p.stockJob and job.isboss==true end
    if mode=='stock' then return manager(src) or (job and p.stockJob and job.name==p.stockJob) end
    return not p.purchaseJob or (job and job.name==p.purchaseJob)
end
local function stock(id) return prefix..'stock:'..id end
local function sales(id) return prefix..'sales:'..id end
local function stable(value)
    if type(value)~='table' then return type(value)..':'..json.encode(value) end
    local keys={} for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local parts={} for _,key in ipairs(keys) do local part=stable(key)..'='..stable(value[key]) parts[#parts+1]=#part..':'..part end
    return '{'..table.concat(parts,';')..'}'
end
local function sku(item) return item.name..'|'..stable(item.metadata or {}) end
local function contents(id) return inv:GetInventoryItems(id) or {} end
local function register(p)
    inv:RegisterStash(stock(p.id),p.name..' 商品',500,100000000,false,nil,vec3(p.coords.x,p.coords.y,p.coords.z))
    inv:RegisterStash(sales(p.id),p.name..' 売上',10,1000000000,false,nil,vec3(p.coords.x,p.coords.y,p.coords.z))
    stashes[stock(p.id)]={id=p.id,kind='stock'} stashes[sales(p.id)]={id=p.id,kind='sales'}
end
local function visible(src)
    local result={} for id,p in pairs(shops) do if p.bucket==GetPlayerRoutingBucket(src) then result[id]=p end end return result
end
local function publish()
    for _,src in ipairs(GetPlayers()) do TriggerClientEvent(prefix..'state',tonumber(src),visible(tonumber(src))) end
end
local function save(p)
    MySQL.query.await('INSERT INTO ptech_omnite_shops (id,payload) VALUES (?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload)',{p.id,json.encode(p)})
end
local function locked(id,fn)
    if not ready then return fail('ショップを初期化中です。') end
    if locks[id] then return fail('処理中です。少し待ってください。') end
    locks[id]=true
    local ok,result=pcall(fn)
    locks[id]=nil
    if not ok then print('[Omnite shops] '..tostring(result)) return fail('処理に失敗しました。') end
    return result
end
local function text(v,n) return type(v)=='string' and utf8.len(v) and utf8.len(v)>0 and utf8.len(v)<=n and not v:find('%c') end
local function job(v) return v==nil or (text(v,48) and v:match('^[%w_-]+$')) end
local function finite(v,min,max) return type(v)=='number' and v==v and v>=min and v<=max end
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await('CREATE TABLE IF NOT EXISTS ptech_omnite_shops (id VARCHAR(48) PRIMARY KEY,payload LONGTEXT NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4')
        for _,row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_shops')) do
            local p=json.decode(row.payload) p.id=row.id p.products=p.products or {} shops[p.id]=p register(p)
        end
        ready=true publish()
    end)
    if not ok then print('[Omnite shops] Initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'list',function(src)
    if not ready then return fail('ショップを初期化中です。') end
    return {ok=true,shops=visible(src),manager=manager(src)}
end)
lib.callback.register(prefix..'save',function(src,input)
    if not manager(src) then return fail('管理者権限と工具箱が必要です。') end
    return locked('settings',function()
        if type(input)~='table' or not text(input.name,64) or not job(input.purchaseJob) or not job(input.stockJob)
            or type(input.finite)~='boolean' or not (input.model==false or text(input.model,100)) then return fail('ショップ設定が不正です。') end
        local old=input.id and shops[input.id]
        if input.id and not old then return fail('ショップが削除されています。') end
        if old and (locks[old.id] or input.revision~=old.revision) then return fail('ショップを開き直してください。') end
        local c=input.coords
        if old and not input.relocate then c=old.coords input.heading=old.heading end
        if not c or not finite(c.x,-10000,10000) or not finite(c.y,-10000,10000) or not finite(c.z,-1000,3000)
            or not finite(input.heading,0,360) then return fail('配置が不正です。') end
        if not old or input.relocate then
            local here=GetEntityCoords(GetPlayerPed(src))
            if (here.x-c.x)^2+(here.y-c.y)^2+(here.z-c.z)^2>9 then return fail('現在地の近くに配置してください。') end
        end
        local p={id=old and old.id or MySQL.scalar.await('SELECT UUID()'),name=input.name,coords=c,heading=input.heading,
            model=input.model,finite=input.finite,purchaseJob=input.purchaseJob,stockJob=input.stockJob,
            bucket=old and old.bucket or GetPlayerRoutingBucket(src),revision=old and old.revision+1 or 1,products=old and old.products or {}}
        save(p) shops[p.id]=p register(p) publish()
        return {ok=true}
    end)
end)
lib.callback.register(prefix..'inventory',function(src,id,kind)
    local p=shops[id]
    if (kind~='stock' and kind~='sales') or not allowed(src,p,kind) or locks[id] then return fail('利用権限がないか、NPCから離れています。') end
    return {ok=true,inventory=kind=='stock' and stock(id) or sales(id)}
end)
lib.callback.register(prefix..'products',function(src,id)
    if not manager(src) or not shops[id] then return fail('管理者のみ操作できます。') end
    local list={}
    for _,item in pairs(contents(stock(id))) do
        local setting=shops[id].products[sku(item)] or {}
        list[#list+1]={slot=item.slot,name=item.name,label=(item.metadata and item.metadata.label) or item.label or item.name,count=item.count,key=sku(item),
            price=setting.price or 0,enabled=setting.enabled==true}
    end
    table.sort(list,function(a,b) return a.slot<b.slot end)
    return {ok=true,products=list,revision=shops[id].revision}
end)
lib.callback.register(prefix..'product',function(src,id,input)
    if not manager(src) then return fail('管理者のみ操作できます。') end
    return locked(id,function()
        local p=shops[id]
        if not p or type(input)~='table' or input.revision~=p.revision then return fail('画面を開き直してください。') end
        local item=inv:GetSlot(stock(id),input.slot)
        if not item or sku(item)~=input.key or type(input.enabled)~='boolean' or not finite(input.price,0,100000000) or input.price%1~=0 then return fail('商品・価格が不正です。') end
        local copy=json.decode(json.encode(p))
        copy.products[input.key]={enabled=input.enabled,price=input.price} copy.revision=copy.revision+1
        save(copy) shops[id]=copy publish()
        return {ok=true}
    end)
end)
local function registerOffer(p)
    local list,map={},{}
    local sorted={} for _,item in pairs(contents(stock(p.id))) do sorted[#sorted+1]=item end
    table.sort(sorted,function(a,b) return a.slot<b.slot end)
    for _,item in ipairs(sorted) do
        local setting=p.products[sku(item)]
        if setting and setting.enabled then
            list[#list+1]={name=item.name,metadata=item.metadata,price=setting.price,currency='money',count=p.finite and item.count or nil}
            map[#list]={stockSlot=item.slot,key=sku(item),price=setting.price}
        end
    end
    local name='omnite_shop_'..p.id
    inv:RegisterShop(name,{name=p.name,inventory=list}) offers[name]={id=p.id,slots=map}
    return name
end
lib.callback.register(prefix..'open',function(src,id)
    local p=shops[id]
    if not allowed(src,p) or locks[id] then return fail('利用権限がないか、ショップから離れています。') end
    return {ok=true,shop=registerOffer(p)}
end)
inv:registerHook('openInventory',function(payload)
    local entry=stashes[tostring(payload.inventoryId)]
    if entry and (locks[entry.id] or not allowed(payload.source,shops[entry.id],entry.kind)) then return false end
end,{inventoryFilter={'^'..prefix}})
inv:registerHook('swapItems',function(payload)
    for _,field in ipairs({'fromInventory','toInventory'}) do
        local entry=stashes[tostring(payload[field])]
        if entry then
            if locks[entry.id] or not allowed(payload.source,shops[entry.id],entry.kind) then return false end
            if entry.kind=='sales' and (type(payload.fromSlot)~='table' or payload.fromSlot.name~='money'
                or (type(payload.toSlot)=='table' and payload.toSlot.name~='money')) then return false end
        end
    end
end,{inventoryFilter={'^'..prefix}})
inv:registerHook('openShop',function(payload)
    local offer=offers[payload.shopType]
    if not offer then return false end
    if not allowed(payload.source,shops[offer.id]) or locks[offer.id] then return false end
    for slot,item in ipairs(payload.items or {}) do
        local line=offer.slots[slot] if not line then return false end item.price=line.price
    end
end,{inventoryFilter={'^omnite_shop_'}})
-- The installed ox_inventory exposes post-hook events with a success flag.
-- Reserve the physical item before purchase, and roll it back when ox rejects the sale.
local pending={}
local nextSale=0
local buyHook=inv:registerHook('buyItem',function(payload)
    local offer=offers[payload.shopType]
    local p=offer and shops[offer.id]
    local line=offer and payload.fromSlot and offer.slots[payload.fromSlot.slot]
    if not p or not line or pending[payload.source] or locks[p.id] or not allowed(payload.source,p) then return false end
    local item=inv:GetSlot(stock(p.id),line.stockSlot)
    local setting=item and p.products[sku(item)]
    if not item or payload.itemName~=item.name or sku(item)~=line.key
        or sku({name=payload.itemName,metadata=payload.fromSlot.metadata or {}})~=line.key
        or not setting or not setting.enabled or payload.currency~='money'
        or not finite(payload.count,1,1000) or payload.count%1~=0 or payload.price~=setting.price
        or payload.totalPrice~=setting.price*payload.count then return false end
    if p.finite and item.count<payload.count then return false end
    if not inv:CanCarryItem(sales(p.id),'money',payload.totalPrice) then return false end
    locks[p.id]=true
    if p.finite and not inv:RemoveItem(stock(p.id),item.name,payload.count,item.metadata,item.slot,false,true) then locks[p.id]=nil return false end
    if payload.totalPrice>0 and not inv:AddItem(sales(p.id),'money',payload.totalPrice) then
        if p.finite then inv:AddItem(stock(p.id),item.name,payload.count,item.metadata,item.slot) end
        locks[p.id]=nil return false
    end
    nextSale=nextSale+1
    payload.omniteSale=nextSale
    pending[payload.source]={token=nextSale,id=p.id,item=item,count=payload.count,cost=payload.totalPrice,finite=p.finite}
end,{inventoryFilter={'^omnite_shop_'}})
AddEventHandler(buyHook,function(success,payload)
    local pendingSale=pending[payload.source]
    if not pendingSale or pendingSale.token~=payload.omniteSale then return end
    pending[payload.source]=nil
    local p=shops[pendingSale.id]
    if not success then
        if pendingSale.cost>0 then assert(inv:RemoveItem(sales(p.id),'money',pendingSale.cost),'Sales rollback failed') end
        if pendingSale.finite then inv:AddItem(stock(p.id),pendingSale.item.name,pendingSale.count,pendingSale.item.metadata,pendingSale.item.slot) end
    end
    locks[pendingSale.id]=nil
end)

lib.callback.register(prefix..'delete',function(src,id,revision)
    if not manager(src) then return fail('管理者のみ操作できます。') end
    return locked(id,function()
        local p=shops[id] if not p or revision~=p.revision or not near(src,p) then return fail('ショップの近くで開き直してください。') end
        for _,stash in ipairs({stock(id),sales(id)}) do
            local items={} for _,item in pairs(contents(stash)) do items[#items+1]=item end
            for _,item in ipairs(items) do
                local count=item.count
                local carry=math.min(count,inv:CanCarryAmount(src,item.name) or 0)
                local removed=inv:RemoveItem(stash,item.name,count,item.metadata,item.slot,false,true)
                assert(removed,'商品の返却に失敗しました。')
                if carry>0 and not inv:AddItem(src,item.name,carry,item.metadata) then carry=0 end
                local remainder=count-carry
                if remainder>0 then
                    local drop=inv:CustomDrop(p.name,{{item.name,remainder,item.metadata}},GetEntityCoords(GetPlayerPed(src)),500,1000000000,p.bucket)
                    if not drop then inv:AddItem(stash,item.name,remainder,item.metadata) error('地面への返却に失敗しました。') end
                end
            end
        end
        MySQL.query.await('DELETE FROM ptech_omnite_shops WHERE id=?',{id})
        inv:RegisterShop('omnite_shop_'..id,{name=p.name,inventory={}})
        shops[id]=nil publish()
        return {ok=true}
    end)
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    ready=false
    for id,p in pairs(shops) do inv:RegisterShop('omnite_shop_'..id,{name=p.name,inventory={}}) end
end)
