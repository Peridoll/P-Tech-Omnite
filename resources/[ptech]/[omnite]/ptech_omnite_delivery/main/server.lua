local prefix = 'ptech_omnite_delivery:'
local locations, missions, locks, cooldowns = {}, {}, {}, {}
local ready, serial = false, 0
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
    return j and j.name == job and (not Config.requireDuty or j.onduty)
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
        or not ({ shop = true, pickup = true, market = true })[p.kind]
        or type(p.coords) ~= 'table' or not number(p.coords.x, -10000, 10000)
        or not number(p.coords.y, -10000, 10000) or not number(p.coords.z, -1000, 3000)
        or not number(p.heading, 0, 360) or not integer(p.bucket, 0, 2147483647) then return false end
    if p.kind == 'shop' then
        return type(p.job) == 'string' and #p.job <= 48 and p.job:match('^[%w_-]+$')
            and integer(p.reward, 0, 10000000) and integer(p.points, 1, 10000)
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
local function account(job)
    return tonumber(MySQL.scalar.await('SELECT points FROM ptech_omnite_delivery_accounts WHERE job = ?', {job})) or 0
end
local function mission(src, p)
    local m = missions[src]
    if m and (m.expires <= os.time() or not p or m.owner ~= p.PlayerData.citizenid
        or not locations[m.shop] or not locations[m.pickup] or not employee(p, m.job)) then
        if m.picked and p and m.owner == p.PlayerData.citizenid then
            exports.ox_inventory:RemoveItem(src, Config.boxItem, 1, {delivery=m.token}, nil, false, false)
        end
        missions[src] = nil
        m = nil
    end
    return m
end
local function locked(src, key, fn)
    if not ready then return fail('配達の初期化が完了していません。') end
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
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_locations (
            id VARCHAR(48) NOT NULL PRIMARY KEY, payload LONGTEXT NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_accounts (
            job VARCHAR(48) NOT NULL PRIMARY KEY, points BIGINT UNSIGNED NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        for _, p in ipairs(Config.locations) do
            assert(valid(p), 'Invalid Config.locations entry')
            assert(not locations[p.id], 'Duplicate Config location ID')
            locations[p.id] = p
        end
        for _, row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_delivery_locations')) do
            local decoded, p = pcall(json.decode, row.payload)
            if decoded and valid(p) and p.id == row.id then locations[p.id] = p end
        end
        ready = true
        publish()
    end)
    if not ok then print('[Omnite delivery] DB initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'state', function(src)
    if not ready then return fail('配達の初期化中です。') end
    if locks['player:'..src] then return fail('処理中です。少し待ってください。') end
    return { ok = true, locations = state(src), mission = mission(src, player(src)), manager = manager(src) }
end)
lib.callback.register(prefix..'manage', function(src, action, input)
    return locked(src, 'settings', function()
        if not manager(src) then return fail('管理者権限と工具箱が必要です。') end
        if action == 'export' then
            local list = {}
            for _, p in pairs(locations) do list[#list+1] = p end
            table.sort(list, function(a,b) return a.id < b.id end)
            return { ok = true, locations = list }
        end
        if action == 'save' then
            if type(input) ~= 'table' then return fail('設定が不正です。') end
            input.bucket = GetPlayerRoutingBucket(src)
            if not valid(input) then return fail('ID・座標・ジョブ・報酬の設定を確認してください。') end
            local old = locations[input.id]
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
        elseif action == 'delete' then
            local p = type(input) == 'string' and locations[input]
            if not p or p.bucket ~= GetPlayerRoutingBucket(src) then return fail('地点が見つかりません。') end
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
    if not ready then return fail('配達の初期化中です。') end
    if locks['player:'..src] then return fail('処理中です。少し待ってください。') end
    local p, shop = player(src), type(id) == 'string' and locations[id]
    if not shop or shop.kind ~= 'shop' or not employee(p, shop.job) or not near(src, shop) then return fail('この店舗の店員のみ利用できます。') end
    return {ok=true, points=account(shop.job), mission=mission(src,p)}
end)
lib.callback.register(prefix..'work', function(src, action, id)
    local shop = type(id) == 'string' and locations[id]
    return locked(src, shop and 'job:'..(shop.job or shop.id), function()
        local p = player(src)
        if not p then return fail('プレイヤーを確認できません。') end
        local m = mission(src, p)
        if action == 'cancel' then
            if m and m.picked then
                exports.ox_inventory:RemoveItem(src, Config.boxItem, 1, {delivery=m.token}, nil, false, false)
            end
            missions[src] = nil
            return {ok=true}
        end
        if action == 'start' then
            if not shop or shop.kind ~= 'shop' or not employee(p, shop.job) or not near(src, shop) then return fail('この店舗の店員のみ受注できます。') end
            if m then return fail('受注中の配達を先に完了してください。') end
            if (cooldowns[p.PlayerData.citizenid] or 0) > os.time() then return fail('次の受注まで少し待ってください。') end
            if not exports.ox_inventory:Items(Config.boxItem) then return fail('配達用の箱アイテムが未登録です。') end
            local choices = {}
            for _, point in pairs(locations) do
                if point.kind == 'pickup' and point.bucket == shop.bucket then choices[#choices+1] = point.id end
            end
            if #choices == 0 then return fail('集荷NPCが登録されていません。') end
            serial = serial+1
            m = {shop=id, pickup=choices[math.random(#choices)], job=shop.job, owner=p.PlayerData.citizenid,
                token=('%d:%d:%d'):format(os.time(), src, serial), expires=os.time()+Config.missionSeconds,
                reward=shop.reward, points=shop.points, picked=false}
            missions[src] = m
            cooldowns[m.owner] = os.time()+Config.cooldownSeconds
            return {ok=true, mission=m}
        end
        if not m then return fail('有効な配達がありません。') end
        if action == 'pickup' then
            local point = locations[m.pickup]
            if id ~= m.pickup or not point or not near(src, point) then return fail('指定された集荷NPCに話しかけてください。') end
            if m.picked then return fail('箱は受取済みです。') end
            local ok = exports.ox_inventory:AddItem(src, Config.boxItem, 1, {delivery=m.token, description=locations[m.shop].label..'への配達用'})
            if not ok then return fail('箱を持てる空きを作ってください。') end
            m.picked = true
            return {ok=true, mission=m}
        end
        if action ~= 'deliver' or id ~= m.shop or not shop or not near(src, shop) or not m.picked then return fail('箱を受け取り、店舗へ納品してください。') end
        local removed = exports.ox_inventory:RemoveItem(src, Config.boxItem, 1, {delivery=m.token}, nil, false, false)
        if not removed then return fail('この配達で受け取った箱が必要です。') end
        local credited, err = pcall(function()
            MySQL.query.await('INSERT INTO ptech_omnite_delivery_accounts (job, points) VALUES (?, ?) ON DUPLICATE KEY UPDATE points = points + VALUES(points)', {m.job,m.points})
        end)
        if not credited then
            exports.ox_inventory:AddItem(src, Config.boxItem, 1, {delivery=m.token})
            error(err)
        end
        if m.reward > 0 and not p.Functions.AddMoney('cash',m.reward,'omnite-delivery') then
            MySQL.update.await('UPDATE ptech_omnite_delivery_accounts SET points = points - ? WHERE job = ? AND points >= ?', {m.points,m.job,m.points})
            exports.ox_inventory:AddItem(src, Config.boxItem, 1, {delivery=m.token})
            return fail('報酬を支給できませんでした。再度納品してください。')
        end
        missions[src] = nil
        return {ok=true, reward=m.reward, points=m.points}
    end)
end)
lib.callback.register(prefix..'buy', function(src, id, productId, quantity)
    local point = type(id) == 'string' and locations[id]
    return locked(src, point and 'job:'..(point.job or point.id), function()
        local p = player(src)
        if not point or not near(src, point) or not p or not integer(quantity,1,Config.maxPurchase) then return fail('購入内容を確認してください。') end
        local product
        for _, entry in ipairs(Config.products) do if entry.id == productId then product = entry break end end
        local cash = point.kind == 'market'
        if not product or not integer(cash and product.cash or product.points,1,cash and 100000000 or 100000) then return fail('この商品の価格は未設定です。') end
        local job = p.PlayerData.job
        if cash then
            if not job or not job.isboss or (Config.requireDuty and not job.onduty) then return fail('店長のみ現金購入できます。') end
            -- Only bosses of jobs registered as a delivery shop may buy materials.
            local registered = false
            for _, shop in pairs(locations) do if shop.kind == 'shop' and shop.job == job.name then registered = true break end end
            if not registered then return fail('登録店舗の店長のみ購入できます。') end
        elseif point.kind ~= 'shop' or not employee(p,point.job) then return fail('この店舗の店員のみ交換できます。') end
        if not exports.ox_inventory:Items(product.item) then return fail('素材アイテムが未登録です。') end
        if not exports.ox_inventory:CanCarryItem(src,product.item,quantity) then return fail('素材を持てる空きを作ってください。') end
        local cost = (cash and product.cash or product.points)*quantity
        if cash then
            if not p.Functions.RemoveMoney('cash',cost,'omnite-supplies') then return fail('現金が足りません。') end
        else
            local changed = MySQL.update.await('UPDATE ptech_omnite_delivery_accounts SET points = points - ? WHERE job = ? AND points >= ?', {cost,point.job,cost})
            if changed ~= 1 then return fail('店舗の箱ポイントが足りません。') end
        end
        local ok = exports.ox_inventory:AddItem(src,product.item,quantity)
        if not ok then
            if cash then p.Functions.AddMoney('cash',cost,'omnite-supplies-refund')
            else MySQL.update.await('UPDATE ptech_omnite_delivery_accounts SET points = points + ? WHERE job = ?', {cost,point.job}) end
            return fail('素材を渡せなかったため返金しました。')
        end
        return {ok=true, message='素材を受け取りました。店舗の飲食スタッシュへ入れてください。'}
    end)
end)
AddEventHandler('playerDropped', function() missions[source] = nil end)
CreateThread(function()
    while true do
        Wait(10000)
        if ready then
            for src in pairs(missions) do
                if not locks['player:'..src] then mission(src,player(src)) end
            end
            publish() -- routing bucket changes are reflected without a resource restart.
        end
    end
end)
