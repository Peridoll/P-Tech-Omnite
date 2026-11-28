local prefix='ptech_omnite_toolbox:treasure:'
local inv=exports.ox_inventory
local points,stashes,claimLocks,active={},{},{},{}
local ready,settingsLock=false,false
local function fail(message) return {ok=false,message=message} end
local function manager(src)
    return (IsPlayerAceAllowed(src,Config.Placement.adminAce) or IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god'))
        and (inv:GetItemCount(src,Config.Placement.item) or 0)>0
end
local function player(src)
    local p=exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData
end
local function near(src,p)
    local ped=GetPlayerPed(src)
    if not p or ped==0 or GetPlayerRoutingBucket(src)~=p.bucket then return false end
    local c=GetEntityCoords(ped)
    return (c.x-p.coords.x)^2+(c.y-p.coords.y)^2+(c.z-p.coords.z)^2<=(Config.Treasure.interactDistance+0.5)^2
end
local function text(value,max)
    if type(value)~='string' or not value:match('%S') or value:find('%c') then return false end
    local length=utf8.len(value) return length and length<=max
end
local function valid(p)
    if type(p)~='table' or not text(p.name,64) or not text(p.model,100) or not p.model:match('^[%w_]+$')
        or type(p.enabled)~='boolean' or type(p.coords)~='table' or not SeatingServer.finite(p.heading,36000) then return false end
    for _,key in ipairs({'x','y','z'}) do if not SeatingServer.finite(p.coords[key],10000) then return false end end
    return true
end
local function stash(id) return prefix..'rewards:'..id end
local function register(p)
    local id=stash(p.id)
    inv:RegisterStash(id,p.name..' 報酬設定',Config.Treasure.slots,Config.Treasure.maxWeight,false,nil,vec3(p.coords.x,p.coords.y,p.coords.z))
    stashes[id]=p.id
end
local function visible(src)
    local result={}
    for id,p in pairs(points) do if p.bucket==GetPlayerRoutingBucket(src) then result[id]=p end end
    return result
end
local function publish()
    for _,value in ipairs(GetPlayers()) do local src=tonumber(value) TriggerClientEvent(prefix..'state',src,visible(src)) end
end
local function record(id,citizenid)
    return MySQL.single.await('SELECT * FROM ptech_omnite_treasure_claims WHERE npc_id=? AND citizenid=?',{id,citizenid})
end
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_treasures (
            id VARCHAR(48) PRIMARY KEY,payload LONGTEXT NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_treasure_claims (
            npc_id VARCHAR(48) NOT NULL,citizenid VARCHAR(64) NOT NULL,display_name VARCHAR(128) NOT NULL,
            payload LONGTEXT NOT NULL,next_index INT NOT NULL DEFAULT 1,status VARCHAR(16) NOT NULL DEFAULT 'ready',
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY(npc_id,citizenid),KEY pending_status(status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        for _,row in ipairs(MySQL.query.await('SELECT * FROM ptech_omnite_treasures') or {}) do
            local decoded,p=pcall(json.decode,row.payload)
            if decoded and valid(p) then p.id=row.id points[p.id]=p register(p)
            else print('[Omnite treasure] Invalid NPC skipped: '..tostring(row.id)) end
        end
    end)
    ready=ok
    if ok then publish() else print('[Omnite treasure] Initialization failed: '..tostring(err)) end
end)
lib.callback.register(prefix..'list',function(src,manage)
    if not ready then return fail('宝箱NPCを初期化中です。') end
    if manage and not manager(src) then return fail('管理者権限と工具箱が必要です。') end
    return {ok=true,points=visible(src)}
end)
local function settings(src,fn)
    if not ready or not manager(src) then return fail('管理者権限と工具箱が必要です。') end
    if settingsLock then return fail('保存処理中です。') end
    settingsLock=true
    local ok,result=pcall(fn)
    settingsLock=false
    if not ok then print('[Omnite treasure] '..tostring(result)) return fail('DB処理に失敗しました。') end
    return result
end
lib.callback.register(prefix..'save',function(src,input)
    return settings(src,function()
        if type(input)~='table' then return fail('設定を確認してください。') end
        local old=input.id and points[input.id]
        if input.id and (not old or old.bucket~=GetPlayerRoutingBucket(src) or old.revision~=input.revision) then return fail('一覧を開き直してください。') end
        if old and (active[old.id] or 0)>0 then return fail('報酬の受取処理中です。少し待ってください。') end
        local count=0 for _ in pairs(points) do count=count+1 end
        if not old and count>=Config.Treasure.maxTotal then return fail('設置上限です。') end
        local coords,heading=old and old.coords,old and old.heading
        if not old or input.relocate then
            local ped=GetPlayerPed(src) if ped==0 then return fail('現在地を取得できません。') end
            local c=GetEntityCoords(ped) coords={x=c.x,y=c.y,z=c.z} heading=GetEntityHeading(ped)
        end
        local p={name=input.name,model=input.model,enabled=input.enabled,coords=coords,heading=heading,
            bucket=GetPlayerRoutingBucket(src),revision=old and old.revision+1 or 1}
        if not valid(p) then return fail('名前・モデルを確認してください。') end
        p.id=old and old.id or MySQL.scalar.await('SELECT UUID()')
        assert(type(p.id)=='string','NPC ID generation failed')
        assert(MySQL.query.await('INSERT INTO ptech_omnite_treasures (id,payload) VALUES (?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload)',{p.id,json.encode(p)})~=nil,'NPC save failed')
        points[p.id]=p register(p) publish()
        return {ok=true,id=p.id}
    end)
end)
local function stashAccess(src,id)
    local p=points[id]
    return ready and manager(src) and p and near(src,p) and not settingsLock and not active[id]
end
lib.callback.register(prefix..'stash',function(src,id)
    if not stashAccess(src,id) then return fail('工具箱を持つ管理者がNPCの近くで操作してください。') end
    return {ok=true,inventory=stash(id)}
end)
inv:registerHook('openInventory',function(payload)
    local id=stashes[tostring(payload.inventoryId)]
    if id and not stashAccess(payload.source,id) then return false end
end,{inventoryFilter={'^'..prefix..'rewards:'}})
inv:registerHook('swapItems',function(payload)
    for _,field in ipairs({'fromInventory','toInventory'}) do
        local id=stashes[tostring(payload[field])]
        if id and not stashAccess(payload.source,id) then return false end
    end
end,{inventoryFilter={'^'..prefix..'rewards:'}})
lib.callback.register(prefix..'delete',function(src,id,revision)
    return settings(src,function()
        local p=points[id]
        if not p or p.revision~=revision or p.bucket~=GetPlayerRoutingBucket(src) then return fail('一覧を開き直してください。') end
        if active[id] then return fail('受取処理中です。') end
        if next(inv:GetInventoryItems(stash(id)) or {}) then return fail('報酬スタッシュの中身を取り出してから削除してください。') end
        local count=tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM ptech_omnite_treasure_claims WHERE npc_id=? AND status!='paid'",{id})) or 0
        if count>0 then return fail('未完了の受取記録があるため削除できません。') end
        assert(MySQL.update.await('DELETE FROM ptech_omnite_treasures WHERE id=?',{id})==1,'NPC delete failed')
        points[id]=nil publish()
        -- 受取済み履歴は保持します。空の設定スタッシュもIDを再利用しません。
        return {ok=true}
    end)
end)
local function copy(value) return json.decode(json.encode(value)) end
local function rewards(p)
    local result={}
    for _,item in pairs(inv:GetInventoryItems(stash(p.id)) or {}) do
        local definition=inv:Items(item.name)
        if not definition or type(item.count)~='number' or item.count<1 or item.count>2147483647 or item.count%1~=0 then error('Invalid reward item') end
        local metadata=copy(item.metadata or {})
        -- 個体IDはox_inventoryに新規発行させ、武器登録やコンテナを共有しません。
        metadata.serial,metadata.registered,metadata.container=nil,nil,nil
        result[#result+1]={name=item.name,count=item.count,metadata=metadata,weight=item.weight or (definition.weight or 0)*item.count,slot=item.slot}
    end
    table.sort(result,function(a,b) return a.slot<b.slot end)
    return result
end
local function stable(value)
    if type(value)~='table' then return type(value)..':'..tostring(value) end
    local keys={} for k in pairs(value) do keys[#keys+1]=k end table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local result={} for _,k in ipairs(keys) do result[#result+1]=stable(k)..'='..stable(value[k]) end
    return '{'..table.concat(result,';')..'}'
end
local function capacity(src,items,first)
    local inventory=inv:GetInventory(src)
    if not inventory then return false end
    local occupied,stacks,required,weight=0,{},0,0
    for _,item in pairs(inventory.items or {}) do
        occupied=occupied+1 stacks[item.name..'|'..stable(item.metadata or {})]=true
    end
    for index=first,#items do
        local item=items[index] local definition=inv:Items(item.name)
        if not definition or not inv:CanCarryItem(src,item.name,item.count,item.metadata) then return false end
        weight=weight+math.max(item.weight or definition.weight*item.count,0)
        local key=item.name..'|'..stable(item.metadata)
        if definition.stack then if not stacks[key] then required=required+1 stacks[key]=true end
        else required=required+item.count end
    end
    return required<=inventory.slots-occupied and inv:CanCarryWeight(src,weight)==true
end
local function identity(src,citizenid,p)
    local data=player(src)
    return data and data.citizenid==citizenid and points[p.id]==p and p.enabled and near(src,p)
end
local function advance(id,citizenid,index,count)
    return MySQL.update.await("UPDATE ptech_omnite_treasure_claims SET next_index=?,status=? WHERE npc_id=? AND citizenid=? AND status='giving' AND next_index=?",
        {index+1,index>=count and 'paid' or 'ready',id,citizenid,index})==1
end
lib.callback.register(prefix..'claim',function(src,id)
    local p=points[id] local data=player(src)
    if not ready or not data or not p or not p.enabled or not near(src,p) then return fail('有効な宝箱NPCの近くで話しかけてください。') end
    local citizenid=data.citizenid
    if settingsLock or claimLocks[citizenid] then return fail('受取処理中です。少し待ってください。') end
    claimLocks[citizenid]=true active[id]=(active[id] or 0)+1
    local ok,result=pcall(function()
        local row=record(id,citizenid)
        if not row then
            local items=rewards(p)
            if #items==0 then return fail('報酬がまだ設定されていません。') end
            if not capacity(src,items,1) then return fail('持ち物の空き・重量を確保してから話しかけてください。') end
            local info=data.charinfo or {}
            local name=(info.firstname or '')..' '..(info.lastname or '')
            local boundary=utf8.offset(name,121) if boundary then name=name:sub(1,boundary-1) end
            MySQL.query.await("INSERT IGNORE INTO ptech_omnite_treasure_claims (npc_id,citizenid,display_name,payload) VALUES (?,?,?,?)",{id,citizenid,name,json.encode(items)})
            row=record(id,citizenid) assert(row,'Claim reservation failed')
        end
        if row.status=='paid' then return fail('このNPCからの報酬は受取済みです。') end
        if row.status~='ready' then return fail('受取状況の確認が必要です。管理者へ連絡してください。') end
        local items=json.decode(row.payload)
        local first=tonumber(row.next_index)
        assert(type(items)=='table' and first and first>=1 and first<=#items,'Invalid claim progress')
        if not capacity(src,items,first) then return fail('持ち物の空き・重量を確保してから話しかけてください。') end
        for index=first,#items do
            if not identity(src,citizenid,p) then return fail('NPCの近くで再度話しかけてください。') end
            local item=items[index]
            if not inv:CanCarryItem(src,item.name,item.count,item.metadata) then return fail('空きを確保して再度話しかけてください。残りの報酬から再開します。') end
            assert(MySQL.update.await("UPDATE ptech_omnite_treasure_claims SET status='giving' WHERE npc_id=? AND citizenid=? AND status='ready' AND next_index=?",{id,citizenid,index})==1,'Claim changed')
            -- DB待ちの間にsourceが再利用されても、別キャラクターへ渡さないよう再確認。
            if not identity(src,citizenid,p) or not inv:CanCarryItem(src,item.name,item.count,item.metadata) then
                MySQL.update.await("UPDATE ptech_omnite_treasure_claims SET status='ready' WHERE npc_id=? AND citizenid=? AND status='giving' AND next_index=?",{id,citizenid,index})
                return fail('受取を中断しました。NPCの近くで持ち物の空きを確認し、再度話しかけてください。')
            end
            local given=inv:AddItem(src,item.name,item.count,copy(item.metadata))
            if not given then
                MySQL.update.await("UPDATE ptech_omnite_treasure_claims SET status='ready' WHERE npc_id=? AND citizenid=? AND status='giving' AND next_index=?",{id,citizenid,index})
                return fail('報酬を渡せませんでした。空きを確保して再度話しかけてください。')
            end
            assert(advance(id,citizenid,index,#items),'Claim completion failed')
        end
        return {ok=true,message='報酬を受け取りました！'}
    end)
    claimLocks[citizenid]=nil active[id]=active[id]-1 if active[id]==0 then active[id]=nil end
    if not ok then print(('[Omnite treasure] Claim %s/%s: %s'):format(id,citizenid,tostring(result))) return fail('受取処理を完了できませんでした。再度話しかけ、確認が必要と出る場合は管理者へ連絡してください。') end
    return result
end)
lib.callback.register(prefix..'reviews',function(src,id)
    if not ready or not manager(src) or not points[id] or points[id].bucket~=GetPlayerRoutingBucket(src) then return fail('管理者のみ操作できます。') end
    return {ok=true,claims=MySQL.query.await("SELECT citizenid,display_name,payload,next_index FROM ptech_omnite_treasure_claims WHERE npc_id=? AND status='giving' ORDER BY updated_at LIMIT 100",{id}) or {}}
end)
lib.callback.register(prefix..'resolve',function(src,id,citizenid,index,delivered)
    if not ready or not manager(src) or not points[id] or points[id].bucket~=GetPlayerRoutingBucket(src) or type(delivered)~='boolean' then return fail('管理者のみ操作できます。') end
    if settingsLock or active[id] or claimLocks[citizenid] then return fail('受取処理中です。') end
    claimLocks[citizenid]=true
    local ok,result=pcall(function()
        local row=record(id,citizenid)
        if not row or row.status~='giving' or tonumber(row.next_index)~=index then return fail('記録が更新されています。') end
        local items=json.decode(row.payload)
        if delivered then assert(advance(id,citizenid,index,#items),'Review completion failed')
        else assert(MySQL.update.await("UPDATE ptech_omnite_treasure_claims SET status='ready' WHERE npc_id=? AND citizenid=? AND status='giving' AND next_index=?",{id,citizenid,index})==1,'Review retry failed') end
        return {ok=true}
    end)
    claimLocks[citizenid]=nil
    if not ok then print('[Omnite treasure] '..tostring(result)) return fail('確認結果を保存できませんでした。') end
    return result
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
