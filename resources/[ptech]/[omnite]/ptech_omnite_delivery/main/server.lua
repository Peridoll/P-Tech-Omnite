local prefix = 'ptech_omnite_delivery:'
local locations, missions, locks, cooldowns = {}, {}, {}, {}
local ready, serial = false, 0
local F=DeliveryFinance
local catalog, catalogRevision = Config.products, 1
local function fail(message) return { ok = false, message = message } end
local function admin(src)
    return IsPlayerAceAllowed(src, Config.adminAce) or IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'god')
end
local function manager(src)
    return admin(src) and (exports.ox_inventory:GetItemCount(src, Config.toolItem) or 0) > 0
end
local function player(src) return exports.qbx_core:GetPlayer(src) end
local function employee(p, job)
    local j = p and p.PlayerData.job
    return j and j.name == job
end
local function near(src, point)
    local ped = GetPlayerPed(src)
    if ped == 0 or GetPlayerRoutingBucket(src) ~= point.bucket then return false end
    local c, p = GetEntityCoords(ped), point.coords
    return (c.x-p.x)^2 + (c.y-p.y)^2 + (c.z-p.z)^2 <= Config.serverDistance^2
end
local function number(n, min, max)
    return type(n) == 'number' and n == n and n >= min and n <= max
end
local function integer(n, min, max) return number(n, min, max) and n % 1 == 0 end
local function valid(p)
    if type(p) ~= 'table' or type(p.id) ~= 'string' or not p.id:match('^[%w_-]+$') or #p.id > 48
        or type(p.label) ~= 'string' or not p.label:match('%S') or #p.label > 160 or p.label:find('%c')
        or not ({ shop = true, pickup = true })[p.kind]
        or type(p.coords) ~= 'table' or not number(p.coords.x, -10000, 10000)
        or not number(p.coords.y, -10000, 10000) or not number(p.coords.z, -1000, 3000)
        or not number(p.heading, 0, 360) or not integer(p.bucket, 0, 2147483647) then return false end
    if p.model and (type(p.model)~='string' or #p.model>100 or not p.model:match('^[%w_]+$')) then return false end
    if p.visibility~=nil and p.visibility~='always' and p.visibility~='mission' then return false end
    if p.kind == 'shop' then
        return type(p.job) == 'string' and #p.job <= 48 and p.job:match('^[%w_-]+$')
            and integer(p.reward, 0, 100000000) and integer(p.points, 1, 10000)
    end
    return true
end
local function validProduct(p)
    return type(p)=='table' and type(p.id)=='string' and #p.id<=48 and p.id:match('^[%w_-]+$')
        and type(p.item)=='string' and #p.item<=100 and p.item:match('^[%w_-]+$')
        and type(p.label)=='string' and p.label:match('%S') and not p.label:find('%c')
        and utf8.len(p.label) and utf8.len(p.label)<=64
        and (p.cash==nil or integer(p.cash,0,100000000))
        and (p.points==nil or integer(p.points,0,100000))
        and ((p.cash or 0)>0 or (p.points or 0)>0)
end
local function validCatalog(list)
    if type(list)~='table' or #list>200 then return false end
    local ids,items={},{}
    for _,p in ipairs(list) do
        if not validProduct(p) or ids[p.id] or items[p.item] then return false end
        ids[p.id],items[p.item]=true,true
    end
    return true
end
local function state(src)
    local list = {}
    for id, p in pairs(locations) do if p.bucket == GetPlayerRoutingBucket(src) then list[id] = p end end
    return list
end
local function publish()
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        TriggerClientEvent(prefix..'locations', src, state(src))
    end
end
local function account(id) return tonumber(F.account(id).points) or 0 end
local function mission(src, p)
    local m = missions[src]
    if m and m.paid then
        F.complete(m)
        missions[src]=nil
        TriggerClientEvent(prefix..'missionEnded',src,m.token,'配達の精算が完了しました。')
        return nil
    end
    if m and (m.expires <= os.time() or not p or m.owner ~= p.PlayerData.citizenid
        or not locations[m.shop] or not locations[m.pickup] or not employee(p, m.job)) then
        F.refund(m)
        if m.picked and p and m.owner == p.PlayerData.citizenid then
            exports.ox_inventory:RemoveItem(src, Config.boxItem, 1, {delivery=m.token}, nil, false, false)
        end
        missions[src] = nil
        TriggerClientEvent(prefix..'missionEnded',src,m.token,
            m.expires <= os.time() and '配達の制限時間が終了しました。' or '所属や配達条件が変わったため、配達を終了しました。')
        m = nil
    end
    return m
end
local function locked(src, key, fn)
    if not ready or not F.ready then return fail('配達の初期化が完了していません。') end
    local playerKey = 'player:'..src
    key = key or playerKey
    if locks[playerKey] or locks[key] then return fail('処理中です。少し待ってください。') end
    locks[playerKey], locks[key] = true, true
    local ok, result = pcall(fn)
    locks[playerKey], locks[key] = nil, nil
    if not ok then print('[Omnite delivery] '..tostring(result)) return fail('処理に失敗しました。') end
    return result
end
MySQL.ready(function()
    local ok, err = pcall(function()
        while not F.ready do Wait(50) end
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_locations (
            id VARCHAR(48) NOT NULL PRIMARY KEY, payload LONGTEXT NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_catalog (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY, payload LONGTEXT NOT NULL,
            revision INT UNSIGNED NOT NULL DEFAULT 1
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        local catalogRows=MySQL.query.await('SELECT * FROM ptech_omnite_delivery_catalog WHERE id = 1')
        if catalogRows[1] then
            local decoded,list=pcall(json.decode,catalogRows[1].payload)
            assert(decoded and validCatalog(list),'Invalid saved delivery catalog')
            catalog,catalogRevision=list,tonumber(catalogRows[1].revision) or 1
            local legacy=#catalog==6
            for _,product in ipairs(catalog) do
                if product.points~=(product.id=='normal' and 1 or 0) then legacy=false end
            end
            if legacy then
                for _,product in ipairs(catalog) do
                    product.points=(product.id=='normal' or product.id=='tobacco_leaf' or product.id=='tea_leaf') and 3 or 5
                end
                MySQL.query.await('UPDATE ptech_omnite_delivery_catalog SET payload=?,revision=revision+1 WHERE id=1',{json.encode(catalog)})
                catalogRevision=catalogRevision+1
            end
        else
            MySQL.query.await('INSERT INTO ptech_omnite_delivery_catalog (id,payload,revision) VALUES (1,?,1)',{json.encode(catalog)})
        end
        -- 廃止済みの大人の飲食物資を保存済みカタログからも除く。他の設定値は保持する。
        local retained={}
        for _,product in ipairs(catalog) do
            if product.item~='pomnite_adult_supply' then retained[#retained+1]=product end
        end
        if #retained~=#catalog then
            local changed=MySQL.update.await('UPDATE ptech_omnite_delivery_catalog SET payload=?,revision=revision+1 WHERE id=1 AND revision=?',
                {json.encode(retained),catalogRevision})
            assert(changed==1,'Failed to remove retired delivery material')
            catalog,catalogRevision=retained,catalogRevision+1
        end
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_accounts (
            job VARCHAR(48) NOT NULL PRIMARY KEY, points BIGINT UNSIGNED NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        for _, p in ipairs(Config.locations) do
            assert(p.kind=='market' or valid(p), 'Invalid Config.locations entry')
            assert(not locations[p.id], 'Duplicate Config location ID')
            if p.kind~="market" then locations[p.id] = p end
        end
        for _, row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_delivery_locations')) do
            local decoded, p = pcall(json.decode, row.payload)
            if decoded and valid(p) and p.id == row.id then locations[p.id] = p end
        end
        for id, point in pairs(locations) do if point.kind == 'shop' then F.register(id) end end
        ready = true
        publish()
    end)
    if not ok then print('[Omnite delivery] DB initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'state', function(src)
    local m=missions[src]
    return locked(src,m and 'shop:'..m.shop,function()
        return { ok = true, locations = state(src), mission = mission(src, player(src)), manager = manager(src) }
    end)
end)
lib.callback.register(prefix..'manage', function(src, action, input)
    local id=(action=='save' and type(input)=='table' and input.id)
        or (action=='delete' and type(input)=='string' and input)
    return locked(src, type(id)=='string' and 'shop:'..id or 'settings', function()
        if not manager(src) then return fail('管理者権限と工具箱が必要です。') end
        if action == 'products' then
            local items={}
            for name,item in pairs(exports.ox_inventory:Items() or {}) do
                items[#items+1]={value=name,label=(item.label or name)..' ['..name..']'}
            end
            table.sort(items,function(a,b) return a.label<b.label end)
            return {ok=true,products=catalog,revision=catalogRevision,items=items}
        end
        if action == 'saveProduct' or action == 'deleteProduct' then
            if type(input)~='table' or input.revision~=catalogRevision then
                return fail('商品一覧が更新されています。画面を開き直してください。')
            end
            local product=input.product
            if action=='saveProduct' and (not validProduct(product) or not exports.ox_inventory:Items(product.item)) then
                return fail('登録済みアイテム・商品名・価格を確認してください。')
            end
            local id=action=='saveProduct' and product.id or input.id
            local list,found={},false
            for _,entry in ipairs(catalog) do
                if entry.id==id then
                    found=true
                    if action=='saveProduct' then list[#list+1]=product end
                else list[#list+1]=entry end
            end
            if action=='saveProduct' and not found then list[#list+1]=product end
            if action=='deleteProduct' and not found then return fail('商品が見つかりません。') end
            if not validCatalog(list) then return fail('同じアイテムの重複、または商品数の上限を確認してください。') end
            local changed=MySQL.update.await('UPDATE ptech_omnite_delivery_catalog SET payload=?,revision=revision+1 WHERE id=1 AND revision=?',
                {json.encode(list),catalogRevision})
            if changed~=1 then return fail('商品を保存できませんでした。画面を開き直してください。') end
            catalog,catalogRevision=list,catalogRevision+1

            return {ok=true}
        end
        if action == 'export' then
            local list = {}
            for _, p in pairs(locations) do list[#list+1] = p end
            table.sort(list, function(a,b) return a.id < b.id end)
            return { ok = true, locations = list, products = catalog }
        end
        if action == 'save' then
            if type(input) ~= 'table' then return fail('設定が不正です。') end
            input.id=input.id or MySQL.scalar.await('SELECT UUID()')
            input.bucket = GetPlayerRoutingBucket(src)
            local old = locations[input.id]
            -- 報酬は店長の専用操作で設定。配置編集からは変更しない。
            if input.kind=='shop' then input.reward=old and old.kind=='shop' and old.reward or Config.defaultReward end
            if not valid(input) then return fail('ID・座標・ジョブ・報酬の設定を確認してください。') end
            if F.used(input.id) then return fail('配達・精算中のNPCは変更できません。') end
            if old and old.bucket ~= input.bucket then return fail('別のバケットで使われているIDです。') end
            local count = 0
            for _ in pairs(locations) do count = count+1 end
            if not old and count >= Config.maxLocations then return fail('配置数の上限です。') end
            if old and json.encode(old) ~= json.encode(input) then
                for _, m in pairs(missions) do
                    if m.shop == input.id or m.pickup == input.id then return fail('配達で使用中の地点は変更できません。') end
                end
            end
            MySQL.query.await('INSERT INTO ptech_omnite_delivery_locations (id, payload) VALUES (?, ?) ON DUPLICATE KEY UPDATE payload = VALUES(payload)', {input.id, json.encode(input)})
            locations[input.id] = input
            if input.kind=='shop' then F.register(input.id) end
        elseif action == 'delete' then
            local p = type(input) == 'string' and locations[input]
            if not p or p.bucket ~= GetPlayerRoutingBucket(src) then return fail('地点が見つかりません。') end
            if F.used(input) then return fail('配達・精算中のNPCは削除できません。') end
            local balance=F.account(input)
            if tonumber(balance.vault)>0 or tonumber(balance.points)>0 then return fail('金庫・ポイントが残っています。先に利用・出金してください。') end
            for _, fixed in ipairs(Config.locations) do if fixed.id == input then return fail('Config登録地点は設定ファイルから削除してください。') end end
            for _, m in pairs(missions) do
                if m.shop == input or m.pickup == input then return fail('配達で使用中の地点は削除できません。') end
            end
            MySQL.query.await('DELETE FROM ptech_omnite_delivery_locations WHERE id = ?', {input})
            locations[input] = nil

        else return fail('操作が不正です。') end
        publish()
        return { ok = true }
    end)
end)
lib.callback.register(prefix..'shop', function(src, id)
    local m=missions[src]
    return locked(src,'shop:'..tostring(m and m.shop or id),function()
        local p, shop = player(src), type(id) == 'string' and locations[id]
        if not shop or shop.kind ~= 'shop' or not employee(p, shop.job) or not near(src, shop) then return fail('この店舗の店員のみ利用できます。') end
        local active=mission(src,p)
        local balance=F.account(shop.id)
        return {ok=true, points=tonumber(balance.points) or 0, vault=tonumber(balance.vault) or 0, reward=shop.reward, boss=p.PlayerData.job.isboss==true, mission=active, products=catalog}
    end)
end)
lib.callback.register(prefix..'work', function(src, action, id)
    local shop = type(id) == 'string' and locations[id]
    local active=missions[src]
    local storeId=action~='start' and active and active.shop or (shop and shop.id)
    return locked(src, storeId and 'shop:'..storeId, function()
        local p = player(src)
        if not p then return fail('プレイヤーを確認できません。') end
        local m = mission(src, p)
        if action == 'cancel' then
            if m then F.refund(m) end
            if m and m.picked then
                exports.ox_inventory:RemoveItem(src, Config.boxItem, 1, {delivery=m.token}, nil, false, false)
            end
            missions[src] = nil
            return {ok=true}
        end
        if action == 'start' then
            if not shop or shop.kind ~= 'shop' or not employee(p, shop.job) or not near(src, shop) then return fail('この店舗の店員のみ受注できます。') end
            if m or F.hasRun(p.PlayerData.citizenid) then return fail('受注・精算中の配達があります。') end
            if (cooldowns[p.PlayerData.citizenid] or 0) > os.time() then return fail('次の受注まで少し待ってください。') end
            if not exports.ox_inventory:Items(Config.boxItem) then return fail('配達用の箱アイテムが未登録です。') end
            local choices = {}
            for _, point in pairs(locations) do
                if point.kind == 'pickup' and point.bucket == shop.bucket then choices[#choices+1] = point.id end
            end
            if #choices == 0 then return fail('配達先NPCが登録されていません。') end
            serial = serial+1
            m = {shop=id, pickup=choices[math.random(#choices)], job=shop.job, owner=p.PlayerData.citizenid,
                token=MySQL.scalar.await('SELECT UUID()'), expires=os.time()+Config.missionSeconds,
                reward=shop.reward, points=shop.points, picked=false}
            if not F.reserve(m) then return fail('金庫に報酬1回分の現金がありません。店長に入金を依頼してください。') end
            missions[src] = m
            cooldowns[m.owner] = os.time()+Config.cooldownSeconds
            return {ok=true, mission=m}
        end
        if not m then return fail('有効な配達がありません。') end
        if (action == 'pickup' or action == 'deliver') and GetVehiclePedIsIn(GetPlayerPed(src),false) ~= 0 then
            return fail('車を降りてNPCに箱を受け渡してください。')
        end
        if action == 'pickup' then
            local point = locations[m.pickup]
            if id ~= m.pickup or not point or not near(src, point) then return fail('箱マークの配達先NPCに話しかけてください。') end
            if m.picked then return fail('箱は受取済みです。') end
            local ok = exports.ox_inventory:AddItem(src, Config.boxItem, 1, {delivery=m.token, description=locations[m.shop].label..'への配達用'})
            if not ok then return fail('箱を持てる空きを作ってください。') end
            m.picked = true
            return {ok=true, mission=m}
        end
        if action ~= 'deliver' or id ~= m.shop or not shop or not near(src, shop) or not m.picked then return fail('箱を受け取り、店舗へ納品してください。') end
        local removed = exports.ox_inventory:RemoveItem(src, Config.boxItem, 1, {delivery=m.token}, nil, false, false)
        if not removed then return fail('この配達で受け取った箱が必要です。') end
        if not F.beginPay(m) then
            exports.ox_inventory:AddItem(src,Config.boxItem,1,{delivery=m.token})
            return fail('配達状態が変わっています。管理者に確認してください。')
        end
        if m.reward>0 and not exports.ox_inventory:AddItem(src,'money',m.reward) then
            F.payFailed(m)
            exports.ox_inventory:AddItem(src,Config.boxItem,1,{delivery=m.token})
            return fail('報酬を持つための空きを作ってください。')
        end
        m.paid=true
        F.complete(m)
        missions[src] = nil
        return {ok=true, reward=m.reward, points=m.points}
    end)
end)
lib.callback.register(prefix..'buy', function(src, id, productId, quantity)
    local point = type(id) == 'string' and locations[id]
    return locked(src, point and 'shop:'..point.id, function()
        local p = player(src)
        if not point or not near(src, point) or not p or not integer(quantity,1,Config.maxPurchase) then return fail('購入内容を確認してください。') end
        local product
        for _, entry in ipairs(catalog) do if entry.id == productId then product = entry break end end
        if point.kind ~= 'shop' or not employee(p,point.job) then return fail('この店舗の店員のみ交換できます。現金購入は商店ショップを利用してください。') end
        if not product or not integer(product.points,1,100000) then return fail('この商品の必要ポイントは未設定です。') end
        if not exports.ox_inventory:Items(product.item) then return fail('素材アイテムが未登録です。') end
        if not exports.ox_inventory:CanCarryItem(src,product.item,quantity) then return fail('素材を持てる空きを作ってください。') end
        local cost = product.points*quantity
        local changed = F.buy(point.id,cost)
        if not changed then return fail('店舗の箱ポイントが足りません。') end
        local ok = exports.ox_inventory:AddItem(src,product.item,quantity)
        if not ok then
            F.refundPoints(point.id,cost)
            return fail('素材を渡せなかったため返金しました。')
        end
        return {ok=true, message='素材を受け取りました。店舗の飲食スタッシュへ入れてください。'}
    end)
end)
AddEventHandler('playerDropped',function()
    local src=source
    CreateThread(function()
        while locks['player:'..src] do Wait(50) end
        local m=missions[src]
        if m then local ok,err=pcall(F.refund,m) if ok then missions[src]=nil else print('[Omnite delivery] Logout refund: '..tostring(err)) end end
    end)
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ready = false
    for src,m in pairs(missions) do if not locks['player:'..src] then pcall(F.refund,m) end end
end)
CreateThread(function()
    while true do
        Wait(10000)
        if ready then
            for src in pairs(missions) do
                local m=missions[src]
                if not locks['player:'..src] and not locks['shop:'..m.shop] then
                    -- A transient DB failure must not stop future expiration/refund checks.
                    locked(src,'shop:'..m.shop,function() mission(src,player(src)) return {ok=true} end)
                end
            end
            publish() -- routing bucket changes are reflected without a resource restart.
        end
    end
end)
lib.callback.register(prefix..'vault',function(src,id,action,amount)
    return locked(src,'shop:'..tostring(id),function()
        local p,point=player(src),locations[id]
        if not point or point.kind~='shop' or not employee(p,point.job) or not p.PlayerData.job.isboss or not near(src,point) then return fail('金庫・報酬設定は店舗の店長のみ操作できます。') end
        if not integer(amount,action=='reward' and 0 or 1,100000000) then return fail('金額が不正です。') end
        if action=='reward' then
            local copy=json.decode(json.encode(point)) copy.reward=amount
            MySQL.query.await('INSERT INTO ptech_omnite_delivery_locations (id,payload) VALUES (?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload)',{id,json.encode(copy)})
            locations[id]=copy publish() return {ok=true}
        end
        if action~='deposit' and action~='withdraw' then return fail('操作が不正です。') end
        local ok,message=F.wallet(src,point,action,amount)
        return ok and {ok=true} or fail(message)
    end)
end)
lib.callback.register(prefix..'reviews',function(src,kind,token,decision)
    return locked(src,'recovery',function()
        if not manager(src) then return fail('管理者のみ操作できます。') end
        if not token then local data=F.reviews() data.ok=true return data end
        F.resolve(kind,token,decision) return {ok=true}
    end)
end)
