local prefix='ptech_omnite_requests:boards:'
local locks={}
PTechRequests.PlacementsReady=false
local function fail(message) return {ok=false,message=message} end
local function authorized(src)
    return (IsPlayerAceAllowed(src,Config.Placement.adminAce) or IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god'))
        and (exports.ox_inventory:GetItemCount(src,Config.Placement.item) or 0)>0
end
local function finite(n,max) return type(n)=='number' and n==n and math.abs(n)<=max end
local function text(s,max) return type(s)=='string' and #s<=max and s:match('%S') and not s:find('%c') end
local function rule(value)
    if type(value)~='table' then return end
    local r={public=value.public==true,jobs={},gangs={},citizenids={}}
    if type(value.citizenids or {})~='table' then return end
    for _,group in ipairs({'jobs','gangs'}) do
        if type(value[group] or {})~='table' then return end
        for name,setting in pairs(value[group] or {}) do
            local grade=type(setting)=='table' and setting.minGrade or setting
            if not text(name,64) or not name:match('^[%w_-]+$') or not finite(grade,100000) or grade<0 or grade%1~=0 then return end
            r[group][name]=type(setting)=='table' and {minGrade=grade,onDuty=setting.onDuty==true} or grade
        end
    end
    if #(value.citizenids or {})>100 then return end
    for _,id in ipairs(value.citizenids or {}) do if not text(id,64) then return end r.citizenids[#r.citizenids+1]=id end
    return r
end
local function visible(src)
    local result={}
    for _,board in ipairs(Config.Boards) do if (board.bucket or 0)==GetPlayerRoutingBucket(src) then result[#result+1]=board end end
    return result
end
local function publish()
    for _,value in ipairs(GetPlayers()) do local src=tonumber(value) TriggerClientEvent(prefix..'state',src,visible(src)) end
end
local function restore(p)
    p.coords=vec3(p.coords.x,p.coords.y,p.coords.z)
    local size=p.size or {x=1.2,y=0.8,z=1.5}
    p.size=vec3(size.x,size.y,size.z)
    p.maxAcceptances=1
    return p
end
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_request_boards (
            id VARCHAR(64) PRIMARY KEY, payload LONGTEXT NOT NULL, revision INT NOT NULL DEFAULT 1
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        local merged={}
        for _,p in ipairs(Config.Boards) do p.revision=0 merged[p.id]=restore(p) end
        for _,row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_request_boards') or {}) do
            local p=json.decode(row.payload)
            if p==false then merged[row.id]=nil else p.id,p.revision=row.id,tonumber(row.revision) merged[row.id]=restore(p) end
        end
        Config.Boards={} for _,p in pairs(merged) do Config.Boards[#Config.Boards+1]=p end
        PTechRequests.PlacementsReady=true publish()
    end)
    if not ok then print('[Omnite requests] Board initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'list',function(src,manage)
    if not PTechRequests.PlacementsReady then return fail('ボードのDB初期化待ちです。') end
    if manage and not authorized(src) then return fail('管理者権限と工具箱が必要です。') end
    return {ok=true,boards=visible(src)}
end)
lib.callback.register(prefix..'save',function(src,input)
    if not PTechRequests.PlacementsReady or not authorized(src) then return fail('管理者権限と工具箱が必要です。') end
    if type(input)~='table' then return fail('入力内容を確認してください。') end
    local old=input.id and PTechRequests.GetBoard(input.id)
    if input.id and (not old or old.revision~=input.revision or (old.bucket or 0)~=GetPlayerRoutingBucket(src)) then return fail('一覧を開き直してください。') end
    if not old and #Config.Boards>=Config.Placement.maxTotal then return fail('設置上限に達しています。') end
    if not text(input.label,192) or (input.type~='general' and input.type~='job') or type(input.permissions)~='table' then return fail('名前・種類・権限を指定してください。') end
    local permissions={}
    for _,action in ipairs({'view','post','accept','deliver','manage'}) do
        permissions[action]=rule(input.permissions[action])
        if not permissions[action] then return fail('権限の設定を確認してください。') end
    end
    local ped=GetPlayerPed(src) if ped==0 then return fail('現在地を取得できません。') end
    local c=GetEntityCoords(ped)
    local coords=old and not input.relocate and old.coords or c
    if #(c-coords)>Config.Placement.maxDistance then return fail('ボードの近くで編集してください。') end
    local p={id=old and old.id,label=input.label,type=input.type,coords=coords,size=old and old.size or vec3(1.2,0.8,1.5),
        rotation=old and not input.relocate and old.rotation or GetEntityHeading(ped),bucket=GetPlayerRoutingBucket(src),
        permissions=permissions,maxAcceptances=1,maxDeliveryQuantity=old and old.maxDeliveryQuantity or 500,
        deliveryPaymentType=old and old.deliveryPaymentType or 'cash',deliveryItems=old and old.deliveryItems or Config.DefaultDeliveryItems,
        fields=old and old.fields or {},revision=old and old.revision+1 or 1}
    local key=input.id or '__create'
    if locks[key] then return fail('保存中です。') end
    locks[key]=true
    local ok=pcall(function()
        if not p.id then p.id='placed_'..MySQL.scalar.await('SELECT UUID()') end
        MySQL.query.await('INSERT INTO ptech_omnite_request_boards (id,payload,revision) VALUES (?,?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload),revision=VALUES(revision)',{p.id,json.encode(p),p.revision})
    end)
    locks[key]=nil
    if not ok then return fail('DBに保存できませんでした。') end
    if old then for i,board in ipairs(Config.Boards) do if board.id==old.id then Config.Boards[i]=p break end end
    else Config.Boards[#Config.Boards+1]=p end
    publish() return {ok=true}
end)
lib.callback.register(prefix..'delete',function(src,id,revision)
    if not PTechRequests.PlacementsReady or not authorized(src) then return fail('管理者権限と工具箱が必要です。') end
    local p=PTechRequests.GetBoard(id)
    if not p or p.revision~=revision or (p.bucket or 0)~=GetPlayerRoutingBucket(src) or locks[id] then return fail('一覧を開き直してください。') end
    locks[id]=true
    local ok=pcall(MySQL.query.await,'INSERT INTO ptech_omnite_request_boards (id,payload,revision) VALUES (?,\'false\',?) ON DUPLICATE KEY UPDATE payload=VALUES(payload),revision=VALUES(revision)',{id,revision+1})
    locks[id]=nil
    if not ok then return fail('DBから削除できませんでした。') end
    for i,board in ipairs(Config.Boards) do if board.id==id then table.remove(Config.Boards,i) break end end
    -- 依頼と受注履歴は削除しません。
    publish() return {ok=true}
end)
CreateThread(function()
    local buckets={}
    while true do
        Wait(2000)
        if PTechRequests.PlacementsReady then
            for _,value in ipairs(GetPlayers()) do local src=tonumber(value) local bucket=GetPlayerRoutingBucket(src)
                if buckets[src]~=bucket then buckets[src]=bucket TriggerClientEvent(prefix..'state',src,visible(src)) end
            end
        end
    end
end)
