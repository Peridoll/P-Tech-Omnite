local prefix = 'ptech_omnite_toolbox:atm:'
local points, locks, ready = {}, {}, false
local function fail(message) return {ok=false,message=message} end
local function admin(src)
    return IsPlayerAceAllowed(src,Config.Placement.adminAce) or IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god')
end
local function authorize(src)
    return ready and admin(src) and (exports.ox_inventory:GetItemCount(src,Config.Placement.item) or 0)>0
end
local function valid(p)
    if type(p)~='table' or type(p.name)~='string' or not p.name:match('%S') or #p.name>192 or p.name:find('%c') then return false end
    local allowed=false
    for _,model in ipairs(Config.ATMs.models) do if model==p.model then allowed=true end end
    if not allowed or type(p.coords)~='table' then return false end
    for _,axis in ipairs({'x','y','z'}) do if not SeatingServer.finite(p.coords[axis],10000) then return false end end
    return SeatingServer.finite(p.heading,36000)
end
local function state(src)
    local result={}
    for id,p in pairs(points) do if p.bucket==GetPlayerRoutingBucket(src) then result[id]=p end end
    return result
end
local function publish()
    for _,src in ipairs(GetPlayers()) do TriggerClientEvent(prefix..'state',tonumber(src),state(tonumber(src))) end
end
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_atms (
            id VARCHAR(64) NOT NULL PRIMARY KEY, payload LONGTEXT NOT NULL, revision INT NOT NULL DEFAULT 1
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        for _,p in ipairs(Config.ATMs.fixed or {}) do
            if valid(p) and type(p.id)=='string' then
                p.revision,p.bucket=0,tonumber(p.bucket) or 0
                points[p.id]=p
            end
        end
        for _,row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_atms') or {}) do
            local decoded,p=pcall(json.decode,row.payload)
            if decoded and p==false then points[row.id]=nil
            elseif decoded and valid(p) then
                p.id,p.revision=row.id,tonumber(row.revision)
                points[p.id]=p
            end
        end
    end)
    ready=ok
    if ok then publish() else print('[Omnite ATM] DB initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'list',function(src,manage)
    if not ready then return fail('ATMのDB初期化待ちです。') end
    if manage and not authorize(src) then return fail('管理者権限と工具箱が必要です。') end
    return {ok=true,points=state(src)}
end)
lib.callback.register(prefix..'save',function(src,p)
    if not authorize(src) then return fail('管理者権限と工具箱が必要です。') end
    if type(p)~='table' then return fail('入力内容を確認してください。') end
    local old=p.id and points[p.id]
    if p.id and (not old or old.revision~=p.revision or old.bucket~=GetPlayerRoutingBucket(src)) then return fail('一覧を開き直してください。') end
    local count=0 for _ in pairs(points) do count=count+1 end
    if not old and count>=Config.ATMs.maxTotal then return fail('設置上限に達しています。') end
    local ped=GetPlayerPed(src)
    if ped==0 then return fail('プレイヤー情報を取得できません。') end
    local c=GetEntityCoords(ped)
    local entry={name=p.name,model=p.model,coords=p.coords,heading=p.heading,bucket=GetPlayerRoutingBucket(src)}
    if old and not p.relocate then entry.coords,entry.heading=old.coords,old.heading end
    if not valid(entry) or #(c-vec3(entry.coords.x,entry.coords.y,entry.coords.z))>Config.Placement.maxDistance then return fail('有効なモデルと近くの設置位置を指定してください。') end
    local key=p.id or '__create'
    if locks[key] then return fail('保存中です。') end
    locks[key]=true
    local ok,id=pcall(function()
        if old then
            MySQL.query.await('INSERT INTO ptech_omnite_atms (id,payload,revision) VALUES (?,?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload),revision=VALUES(revision)',
                {old.id,json.encode(entry),old.revision+1})
            return old.id
        end
        -- UUIDはDBで生成し、再起動後も衝突しないIDにします。
        local newId=MySQL.scalar.await('SELECT UUID()')
        assert(type(newId)=='string')
        MySQL.insert.await('INSERT INTO ptech_omnite_atms (id,payload,revision) VALUES (?,?,1)',{newId,json.encode(entry)})
        return newId
    end)
    locks[key]=nil
    if not ok then return fail('DBに保存できませんでした。') end
    entry.id,entry.revision=id,old and old.revision+1 or 1
    points[id]=entry publish()
    return {ok=true}
end)
lib.callback.register(prefix..'delete',function(src,id,revision)
    if not authorize(src) then return fail('管理者権限と工具箱が必要です。') end
    local p=points[id]
    if not p or p.revision~=revision or p.bucket~=GetPlayerRoutingBucket(src) or locks[id] then return fail('一覧を開き直してください。') end
    locks[id]=true
    -- Config由来の地点も再起動で復活しないよう削除記録を残します。
    local ok=pcall(MySQL.query.await,'INSERT INTO ptech_omnite_atms (id,payload,revision) VALUES (?,\'false\',?) ON DUPLICATE KEY UPDATE payload=VALUES(payload),revision=VALUES(revision)',{id,revision+1})
    locks[id]=nil
    if not ok then return fail('DBから削除できませんでした。') end
    points[id]=nil publish() return {ok=true}
end)
CreateThread(function()
    local buckets={}
    while true do
        Wait(2000)
        if ready then
            for _,value in ipairs(GetPlayers()) do
                local src=tonumber(value) local bucket=GetPlayerRoutingBucket(src)
                if buckets[src]~=bucket then buckets[src]=bucket TriggerClientEvent(prefix..'state',src,state(src)) end
            end
        end
    end
end)
