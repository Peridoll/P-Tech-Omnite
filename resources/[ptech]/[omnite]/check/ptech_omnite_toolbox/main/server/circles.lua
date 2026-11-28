local S = SeatingServer
local prefix = 'ptech_omnite_toolbox:circle:'
local points, locks, members, escaped, requests = {}, {}, {}, {}, {}
local ready = false
-- Kept server-side; never sent in the public circle state.
local escapePassword = '4155'
local function fail(message) return {ok=false,message=message} end
local function admin(src)
    return IsPlayerAceAllowed(src, Config.Placement.adminAce)
        or IsPlayerAceAllowed(src, 'admin')
        or IsPlayerAceAllowed(src, 'god')
end
local function rate(src)
    local now=GetGameTimer()
    if requests[src] and now-requests[src]<750 then return false end
    requests[src]=now
    return true
end
local function point(p)
    return type(p)=='table' and S.finite(p.x,10000) and S.finite(p.y,10000)
        and S.finite(p.z,10000) and S.finite(p.heading,36000)
end
local function inside(c,p)
    return (c.x-p.center.x)^2+(c.y-p.center.y)^2<=p.radius^2
end
local function valid(p)
    if type(p)~='table' or type(p.name)~='string' or not p.name:match('%S') or p.name:find('%c')
        or (p.kind~=nil and p.kind~='starter' and p.kind~='npc_repellent')
        or type(p.enabled)~='boolean' or not point(p.center)
        or not S.finite(p.radius,Config.Circles.maxRadius) or p.radius<2 then return false end
    if not utf8.len(p.name) or utf8.len(p.name)>64 then return false end
    if p.kind=='npc_repellent' then return true end
    if type(p.message)~='string'
        or not utf8.len(p.message) or utf8.len(p.message)>256 or p.message:find('%c')
        or not point(p.destination)
        or not S.finite(p.delay,Config.Circles.maxDelay) or p.delay<0 or p.delay%1~=0 then return false end
    return inside(p.destination,p)
end
local function public(p)
    return {id=p.id,kind=p.kind or 'starter',name=p.name,center=p.center,destination=p.destination,radius=p.radius,
        delay=p.delay,message=p.message,enabled=p.enabled,bucket=p.bucket,revision=p.revision}
end
local function state(src)
    local result={}
    for id,p in pairs(points) do
        if p.bucket==GetPlayerRoutingBucket(src) then result[id]=public(p) end
    end
    return result
end
function S.sendCircles(src)
    if ready then TriggerClientEvent(prefix..'state',src,state(src),GetPlayerRoutingBucket(src)) end
end
local function publish()
    for _,src in ipairs(GetPlayers()) do S.sendCircles(tonumber(src)) end
end
local function clearCircle(id,preserve)
    for src,list in pairs(members) do
        if preserve and list[id] then list[id]={revision=preserve.revision} else list[id]=nil end
        TriggerClientEvent(prefix..'warning',src,id,false)
    end
    for _,list in pairs(escaped) do list[id]=nil end
end
MySQL.ready(function()
    local ok,rows=pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS ptech_omnite_circles (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                payload LONGTEXT NOT NULL, bucket INT NOT NULL DEFAULT 0,
                revision INT NOT NULL DEFAULT 1,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        return MySQL.query.await('SELECT * FROM ptech_omnite_circles')
    end)
    if not ok or type(rows)~='table' then print('[Toolbox] Circle DB initialization failed.') return end
    for _,row in ipairs(rows) do
        local decoded,p=pcall(json.decode,row.payload)
        if decoded and valid(p) then
            p.id,p.bucket,p.revision=tostring(row.id),tonumber(row.bucket) or 0,tonumber(row.revision) or 1
            points[p.id]=p
        else print('[Toolbox] Invalid circle skipped: '..tostring(row.id)) end
    end
    ready=true
    publish()
end)
lib.callback.register(prefix..'list',function(src)
    if not ready then return fail('サークルDBの準備ができていません。') end
    return {ok=true,points=state(src),bucket=GetPlayerRoutingBucket(src),admin=admin(src)}
end)
lib.callback.register(prefix..'appearance',function(src,id)
    if not ready or not rate(src) then return fail('少し待ってから操作してください。') end
    local p=points[tostring(id)]
    local ped=GetPlayerPed(src)
    if not p or p.kind=='npc_repellent' or not p.enabled or p.bucket~=GetPlayerRoutingBucket(src) or ped==0
        or not inside(GetEntityCoords(ped),p) or GetVehiclePedIsIn(ped,false)~=0 or S.hasSeat(src) then
        return fail('有効なサークル内で、徒歩で立った状態で操作してください。')
    end
    return {ok=true}
end)
lib.callback.register(prefix..'capture',function(src)
    if not admin(src) then return fail('管理者のみ操作できます。') end
    local ped=GetPlayerPed(src)
    if ped==0 or GetVehiclePedIsIn(ped,false)~=0 or S.hasSeat(src) then return fail('徒歩で立った状態で指定してください。') end
    local c=GetEntityCoords(ped)
    return {ok=true,point={x=c.x,y=c.y,z=c.z,heading=GetEntityHeading(ped)%360}}
end)
lib.callback.register(prefix..'save',function(src,input)
    if not admin(src) then return fail('管理者のみ操作できます。') end
    if not ready or not rate(src) then return fail('少し待ってから操作してください。') end
    if not valid(input) then return fail('名前・中心・半径などの設定値を確認してください。スターターの連れ戻し先は範囲内に指定してください。') end
    local id=input.id and tostring(input.id)
    local old=id and points[id]
    local bucket=GetPlayerRoutingBucket(src)
    if id and (not old or old.bucket~=bucket or old.revision~=input.revision) then return fail('情報が更新されています。開き直してください。') end
    if old and (old.kind or 'starter')~=(input.kind or 'starter') then return fail('サークルの種類は変更できません。') end
    local count=0
    for _ in pairs(points) do count=count+1 end
    if not id and count>=Config.Circles.maxTotal then return fail('登録上限に達しています。') end
    local key=id or '__create'
    if locks[key] then return fail('保存処理中です。') end
    locks[key]=true
    local p={kind=input.kind or 'starter',name=input.name,center=input.center,destination=input.destination,radius=input.radius,
        delay=input.delay,message=input.message,enabled=input.enabled,bucket=bucket,revision=old and old.revision+1 or 1}
    if p.kind=='npc_repellent' then p.destination,p.delay,p.message=nil,nil,nil end
    local ok,result=pcall(function()
        if old then
            return MySQL.update.await('UPDATE ptech_omnite_circles SET payload=?,revision=revision+1 WHERE id=? AND revision=?',
                {json.encode(p),id,old.revision})==1
        end
        local inserted=MySQL.insert.await('INSERT INTO ptech_omnite_circles (payload,bucket) VALUES (?,?)',{json.encode(p),bucket})
        if inserted then id=tostring(inserted) return true end
        return false
    end)
    locks[key]=nil
    if not ok or not result then return fail('DBに保存できませんでした。') end
    p.id=id
    points[id]=p
    clearCircle(id,p.enabled and p.kind=='starter' and p or nil)
    publish()
    return {ok=true,id=id}
end)
lib.callback.register(prefix..'delete',function(src,id,revision)
    if not admin(src) then return fail('管理者のみ操作できます。') end
    if not ready or not rate(src) then return fail('少し待ってから操作してください。') end
    id=tostring(id)
    local p=points[id]
    if not p or p.bucket~=GetPlayerRoutingBucket(src) or p.revision~=revision then return fail('情報が更新されています。') end
    if locks[id] then return fail('保存処理中です。') end
    locks[id]=true
    local ok,n=pcall(MySQL.update.await,'DELETE FROM ptech_omnite_circles WHERE id=? AND revision=?',{id,revision})
    locks[id]=nil
    if not ok or n~=1 then return fail('DBから削除できませんでした。') end
    points[id]=nil
    clearCircle(id)
    publish()
    return {ok=true}
end)
local function move(src,d)
    S.release(src)
    local ped=GetPlayerPed(src)
    SetEntityCoords(ped,d.x,d.y,d.z,false,false,false,false)
    SetEntityHeading(ped,d.heading)
    TriggerClientEvent(prefix..'travel',src,d)
end
lib.callback.register(prefix..'escape',function(src,id,password)
    if not ready or not rate(src) then return fail('少し待ってから操作してください。') end
    local p=points[tostring(id)]
    if not p or p.kind=='npc_repellent' or p.bucket~=GetPlayerRoutingBucket(src) or not S.near(src,p.center,Config.Circles.interactDistance+0.5) then
        return fail('サークルの編集ポイントに近づいてください。')
    end
    if type(password)~='string' or password~=escapePassword then return fail('脱出パスワードが違います。') end
    if GetPlayerPed(src)==0 then return fail('プレイヤーを取得できません。') end
    -- Release all memberships so overlapping circles cannot immediately pull an escapee back.
    members[src]={}
    escaped[src]={}
    for key,entry in pairs(points) do
        if entry.kind~='npc_repellent' and entry.enabled and entry.bucket==p.bucket then escaped[src][key]=entry.revision end
    end
    TriggerClientEvent(prefix..'clearWarnings',src)
    move(src,Config.Circles.escapeDestination)
    return {ok=true}
end)

-- Membership, countdowns and destinations are authoritative on the server.
function S.tickCircles()
    if not ready then return end
    local now=GetGameTimer()
    for _,sourceId in ipairs(GetPlayers()) do
        local src=tonumber(sourceId)
        local ped=GetPlayerPed(src)
        if ped~=0 then
            local c,bucket=GetEntityCoords(ped),GetPlayerRoutingBucket(src)
            members[src]=members[src] or {}
            escaped[src]=escaped[src] or {}
            for id,p in pairs(points) do
                local m=members[src][id]
                if p.kind=='npc_repellent' or not p.enabled or p.bucket~=bucket or (m and m.revision~=p.revision) then
                    if m then TriggerClientEvent(prefix..'warning',src,id,false) end
                    members[src][id],escaped[src][id]=nil,nil
                elseif escaped[src][id] then
                    if not inside(c,p) then escaped[src][id]=nil end
                elseif inside(c,p) then
                    if m and m.deadline then TriggerClientEvent(prefix..'warning',src,id,false) end
                    members[src][id]={revision=p.revision}
                elseif m then
                    if not m.deadline then
                        m.deadline=now+p.delay*1000
                        TriggerClientEvent(prefix..'warning',src,id,true,p.message,p.delay)
                    end
                    if now>=m.deadline then
                        move(src,p.destination)
                        c=p.destination
                        m.deadline=nil
                        TriggerClientEvent(prefix..'warning',src,id,false)
                    end
                end
            end
        end
    end
end
CreateThread(function()
    while true do S.tickCircles() Wait(250) end
end)
AddEventHandler('playerDropped',function()
    members[source],escaped[source],requests[source]=nil,nil,nil
end)
