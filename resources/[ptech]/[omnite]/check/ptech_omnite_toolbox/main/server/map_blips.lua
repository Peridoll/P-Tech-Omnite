local prefix='ptech_omnite_toolbox:mapblip:'
local points,ready,mutating={},false,false
local function fail(message) return {ok=false,message=message} end
local function authorize(src)
    return (IsPlayerAceAllowed(src,Config.Placement.adminAce) or IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god'))
        and (exports.ox_inventory:GetItemCount(src,Config.Placement.item) or 0)>0
end
local function number(value,min,max,integer)
    return type(value)=='number' and value==value and value>=min and value<=max and (not integer or value%1==0)
end
local function valid(p)
    if type(p)~='table' or type(p.name)~='string' or not p.name:match('%S') or p.name:find('%c') then return false end
    local length=utf8.len(p.name)
    if not length or length>64 or type(p.coords)~='table' then return false end
    for _,axis in ipairs({'x','y','z'}) do if not number(p.coords[axis],-10000,10000) then return false end end
    return number(p.sprite,1,65535,true) and number(p.colour,0,255,true) and number(p.scale,0.1,5.0)
        and type(p.shortRange)=='boolean' and type(p.enabled)=='boolean'
        and (p.minimap==nil or type(p.minimap)=='boolean')
end
local function state(src)
    local result={}
    for id,p in pairs(points) do if p.bucket==GetPlayerRoutingBucket(src) then result[id]=p end end
    return result
end
local function publish()
    for _,value in ipairs(GetPlayers()) do local src=tonumber(value) TriggerClientEvent(prefix..'state',src,state(src)) end
end
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_map_blips (
            id VARCHAR(64) NOT NULL PRIMARY KEY, payload LONGTEXT NOT NULL, revision INT NOT NULL DEFAULT 1
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        local restored={}
        for _,p in ipairs(Config.MapBlips.fixed or {}) do
            if valid(p) and type(p.id)=='string' and #p.id<=64 and number(p.bucket or 0,0,2147483647,true) then
                local entry=json.decode(json.encode(p))
                entry.minimap=p.minimap==true
                entry.bucket,entry.revision=p.bucket or 0,0
                restored[p.id]=entry
            end
        end
        for _,row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_map_blips') or {}) do
            local decoded,p=pcall(json.decode,row.payload)
            if decoded and p==false then restored[row.id]=nil
            elseif decoded and valid(p) and number(p.bucket,0,2147483647,true) then
                p.id,p.revision=row.id,tonumber(row.revision) or 1
                p.minimap=p.minimap==true
                restored[row.id]=p
            else print('[Omnite map blips] Invalid entry skipped: '..tostring(row.id)) end
        end
        points=restored
    end)
    ready=ok
    if ok then publish() else print('[Omnite map blips] DB initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'list',function(src,manage)
    if not ready then return fail('マップブリップのDB初期化待ちです。') end
    if manage and not authorize(src) then return fail('管理者権限と工具箱が必要です。') end
    return {ok=true,points=state(src)}
end)
local function mutation(src,fn)
    if not ready then return fail('マップブリップのDB初期化待ちです。') end
    if not authorize(src) then return fail('管理者権限と工具箱が必要です。') end
    if mutating then return fail('保存処理中です。少し待ってください。') end
    mutating=true
    local ok,result=pcall(fn)
    mutating=false
    if not ok then print('[Omnite map blips] Save failed: '..tostring(result)) return fail('DBに保存できませんでした。') end
    return result
end
lib.callback.register(prefix..'save',function(src,input)
    return mutation(src,function()
        if type(input)~='table' then return fail('入力内容を確認してください。') end
        local old=input.id and points[input.id]
        if input.id and (not old or old.revision~=input.revision or old.bucket~=GetPlayerRoutingBucket(src)) then return fail('情報が更新されています。一覧を開き直してください。') end
        local count=0 for _ in pairs(points) do count=count+1 end
        if not old and count>=Config.MapBlips.maxTotal then return fail('設置上限に達しています。') end
        local coords=old and old.coords
        if not old or input.relocate==true then
            local ped=GetPlayerPed(src)
            if ped==0 then return fail('現在地を取得できません。') end
            local c=GetEntityCoords(ped)
            coords={x=c.x,y=c.y,z=c.z}
        end
        local p={name=input.name,coords=coords,sprite=input.sprite,colour=input.colour,scale=input.scale,
            minimap=input.minimap,shortRange=input.shortRange,enabled=input.enabled,bucket=GetPlayerRoutingBucket(src)}
        if not valid(p) then return fail('名前・アイコンID・色・大きさを確認してください。') end
        p.minimap=p.minimap==true
        p.shortRange=not p.minimap
        local id=old and old.id or MySQL.scalar.await('SELECT UUID()')
        assert(type(id)=='string' and #id<=64,'Invalid map blip ID')
        local revision=old and old.revision+1 or 1
        assert(MySQL.query.await('INSERT INTO ptech_omnite_map_blips (id,payload,revision) VALUES (?,?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload),revision=VALUES(revision)',{id,json.encode(p),revision})~=nil,'Map blip write failed')
        p.id,p.revision=id,revision
        points[id]=p publish()
        return {ok=true,id=id}
    end)
end)
lib.callback.register(prefix..'delete',function(src,id,revision)
    return mutation(src,function()
        local p=points[id]
        if not p or p.revision~=revision or p.bucket~=GetPlayerRoutingBucket(src) then return fail('情報が更新されています。一覧を開き直してください。') end
        -- Configにも残っているIDが再起動後に復活しないよう削除記録を保存します。
        assert(MySQL.query.await('INSERT INTO ptech_omnite_map_blips (id,payload,revision) VALUES (?,\'false\',?) ON DUPLICATE KEY UPDATE payload=VALUES(payload),revision=VALUES(revision)',{id,revision+1})~=nil,'Map blip delete failed')
        points[id]=nil publish()
        return {ok=true}
    end)
end)
local buckets={}
CreateThread(function()
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
AddEventHandler('playerDropped',function() buckets[source]=nil end)
