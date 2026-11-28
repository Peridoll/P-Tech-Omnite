local prefix='ptech_omnite_toolbox:jobstash:'
local inv=exports.ox_inventory
local points,stashIds={},{}
local ready,mutating=false,false
local function fail(message) return {ok=false,message=message} end
local function manager(src)
    return (IsPlayerAceAllowed(src,Config.Placement.adminAce) or IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god'))
        and (inv:GetItemCount(src,Config.Placement.item) or 0)>0
end
local function text(value,max)
    local length=type(value)=='string' and utf8.len(value)
    return length and length>0 and length<=max and value:match('%S') and not value:find('%c')
end
local function integer(n,min,max) return type(n)=='number' and n==n and n%1==0 and n>=min and n<=max end
local function valid(p)
    if type(p)~='table' or not text(p.name,64) or not text(p.job,64) or not p.job:match('^[%w_-]+$')
        or not integer(p.minGrade,0,100000) or not integer(p.slots,1,Config.JobStashes.maxSlots)
        or not integer(p.maxWeight,1,Config.JobStashes.weightLimit) or type(p.enabled)~='boolean'
        or type(p.coords)~='table' then return false end
    for _,axis in ipairs({'x','y','z'}) do if not SeatingServer.finite(p.coords[axis],10000) then return false end end
    return true
end
local function stash(id) return prefix..id end
local function register(p)
    local name=stash(p.id)
    -- owner=falseで、同じ設置IDをJOBの全利用者が共有します。
    inv:RegisterStash(name,p.name,p.slots,p.maxWeight,false,{[p.job]=p.minGrade},vec3(p.coords.x,p.coords.y,p.coords.z),p.bucket)
    stashIds[name]=p.id
end
local function authorized(src,p)
    if not ready or mutating or not p or not p.enabled or GetPlayerRoutingBucket(src)~=p.bucket then return false end
    local ped=GetPlayerPed(src) if ped==0 then return false end
    local player=exports.qbx_core:GetPlayer(src)
    local job=player and player.PlayerData.job
    local grade=job and (type(job.grade)=='table' and job.grade.level or job.grade)
    if not job or job.name~=p.job or (tonumber(grade) or 0)<p.minGrade then return false end
    local c=GetEntityCoords(ped)
    return (c.x-p.coords.x)^2+(c.y-p.coords.y)^2+(c.z-p.coords.z)^2<=(Config.JobStashes.interactDistance+0.5)^2
end
local function visible(src)
    local result={} for id,p in pairs(points) do if p.bucket==GetPlayerRoutingBucket(src) then result[id]=p end end return result
end
local function publish()
    for _,value in ipairs(GetPlayers()) do local src=tonumber(value) TriggerClientEvent(prefix..'state',src,visible(src)) end
end
local function closeViewers(id)
    local inventory=inv:GetInventory(stash(id))
    for src in pairs(inventory and inventory.openedBy or {}) do TriggerClientEvent('ox_inventory:closeInventory',src,true) end
end
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_job_stashes (
            id VARCHAR(48) NOT NULL PRIMARY KEY,payload LONGTEXT NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        for _,row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_job_stashes') or {}) do
            local decoded,p=pcall(json.decode,row.payload)
            if decoded and valid(p) and integer(p.bucket or 0,0,2147483647) then
                p.id,p.bucket,p.revision=row.id,p.bucket or 0,tonumber(p.revision) or 1
                points[p.id]=p register(p)
            else print('[Omnite job stash] Invalid placement skipped: '..tostring(row.id)) end
        end
    end)
    ready=ok
    if ok then publish() else print('[Omnite job stash] Initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'list',function(src,manage)
    if not ready then return fail('ジョブ共有スタッシュを初期化中です。') end
    if manage and not manager(src) then return fail('管理者権限と工具箱が必要です。') end
    return {ok=true,points=visible(src),jobs=manage and exports.qbx_core:GetJobs() or nil}
end)
local function mutation(src,fn)
    if not ready or not manager(src) then return fail('管理者権限と工具箱が必要です。') end
    if mutating then return fail('保存処理中です。') end
    mutating=true
    local ok,result=pcall(fn)
    mutating=false
    if not ok then print('[Omnite job stash] '..tostring(result)) return fail('保存に失敗しました。') end
    return result
end
lib.callback.register(prefix..'save',function(src,input)
    return mutation(src,function()
        if type(input)~='table' then return fail('設定を確認してください。') end
        local old=input.id and points[input.id]
        if input.id and (not old or old.revision~=input.revision or old.bucket~=GetPlayerRoutingBucket(src)) then return fail('一覧を開き直してください。') end
        local count=0 for _ in pairs(points) do count=count+1 end
        if not old and count>=Config.JobStashes.maxTotal then return fail('設置上限です。') end
        local coords=old and old.coords
        if not old or input.relocate==true then
            local ped=GetPlayerPed(src) if ped==0 then return fail('現在地を取得できません。') end
            local c=GetEntityCoords(ped) coords={x=c.x,y=c.y,z=c.z}
        end
        local p={name=input.name,job=input.job,minGrade=input.minGrade,slots=input.slots,maxWeight=input.maxWeight,
            enabled=input.enabled,coords=coords,bucket=GetPlayerRoutingBucket(src),revision=old and old.revision+1 or 1}
        if not valid(p) or not exports.qbx_core:GetJobs()[p.job] then return fail('JOB・最低階級・容量などの設定を確認してください。') end
        if old then
            local inventory=inv:GetInventory(stash(old.id))
            if not inventory then return fail('現在のスタッシュを確認できません。再度操作してください。') end
            if inventory.weight>p.maxWeight then return fail('中身の重量より小さい容量にはできません。先に中身を整理してください。') end
            for slot,item in pairs(inventory.items or {}) do
                if item and (tonumber(item.slot) or tonumber(slot) or math.huge)>p.slots then return fail('縮小後の範囲外にアイテムがあります。先に中身を整理してください。') end
            end
            closeViewers(old.id)
        end
        p.id=old and old.id or MySQL.scalar.await('SELECT UUID()')
        assert(type(p.id)=='string','Stash ID generation failed')
        assert(MySQL.query.await('INSERT INTO ptech_omnite_job_stashes (id,payload) VALUES (?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload)',{p.id,json.encode(p)})~=nil,'Placement save failed')
        points[p.id]=p register(p) publish()
        return {ok=true,id=p.id}
    end)
end)
lib.callback.register(prefix..'open',function(src,id)
    if not authorized(src,points[id]) then return fail('JOB・階級・距離などの利用条件を満たしていません。') end
    return {ok=true,inventory=stash(id)}
end)
inv:registerHook('openInventory',function(payload)
    local id=stashIds[tostring(payload.inventoryId)]
    if id and not authorized(payload.source,points[id]) then return false end
end,{inventoryFilter={'^'..prefix}})
inv:registerHook('swapItems',function(payload)
    for _,field in ipairs({'fromInventory','toInventory'}) do
        local id=stashIds[tostring(payload[field])]
        if id and not authorized(payload.source,points[id]) then return false end
    end
end,{inventoryFilter={'^'..prefix}})
RegisterNetEvent(prefix..'checkAccess',function()
    local src=source
    local inventory=inv:GetInventory(src)
    local id=inventory and stashIds[tostring(inventory.open)]
    if id and not authorized(src,points[id]) then TriggerClientEvent('ox_inventory:closeInventory',src,true) end
end)
lib.callback.register(prefix..'delete',function(src,id,revision)
    return mutation(src,function()
        local p=points[id]
        if not p or p.revision~=revision or p.bucket~=GetPlayerRoutingBucket(src) then return fail('一覧を開き直してください。') end
        local inventory=inv:GetInventory(stash(id))
        if not inventory then return fail('スタッシュを確認できません。') end
        if next(inventory.items or {}) then return fail('中身を空にしてから削除してください。') end
        closeViewers(id)
        assert(MySQL.update.await('DELETE FROM ptech_omnite_job_stashes WHERE id=?',{id})==1,'Placement delete failed')
        inv:RegisterStash(stash(id),p.name,p.slots,p.maxWeight,false,{},vec3(p.coords.x,p.coords.y,p.coords.z),p.bucket)
        -- 登録IDのフックは残し、削除済みIDを直接指定しても開けないようにします。
        points[id]=nil publish()
        return {ok=true}
    end)
end)
local buckets={}
CreateThread(function()
    while true do
        Wait(2000)
        if ready then for _,value in ipairs(GetPlayers()) do
            local src=tonumber(value) local bucket=GetPlayerRoutingBucket(src)
            if buckets[src]~=bucket then buckets[src]=bucket TriggerClientEvent(prefix..'state',src,visible(src)) end
        end end
    end
end)
AddEventHandler('playerDropped',function() buckets[source]=nil end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    ready=false
    for id,p in pairs(points) do
        pcall(function()
            closeViewers(id)
            -- フックが解除された後も、停止中のスタッシュは通常の開き方で利用させません。
            inv:RegisterStash(stash(id),p.name,p.slots,p.maxWeight,false,{},vec3(p.coords.x,p.coords.y,p.coords.z),p.bucket)
        end)
    end
end)
