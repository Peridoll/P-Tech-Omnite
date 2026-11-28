local S=SeatingServer
local prefix='ptech_omnite_toolbox:teleport:'
local points,drafts,locks,requests,uses={},{},{},{},{}
local ready=false
local nextDraft=0
local function fail(message) return {ok=false,message=message} end
local function player(src)
    local p=exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData
end
local function authorize(src)
    local p=player(src)
    if not ready then return nil,fail('テレポーターDBの準備ができていません。') end
    if not (IsPlayerAceAllowed(src,Config.Placement.adminAce) or IsPlayerAceAllowed(src,'admin') or IsPlayerAceAllowed(src,'god')) then
        return nil,fail('管理者のみ操作できます。')
    end
    if not p or (exports.ox_inventory:GetItemCount(src,Config.Placement.item) or 0)<1 then
        return nil,fail('工具箱を所持していません。')
    end
    return p.citizenid
end
local function label(value)
    if type(value)~='string' or value:find('%c') or not value:match('%S') then return false end
    local n=utf8.len(value)
    return n and n<=64
end
local function endpoint(p)
    return type(p)=='table' and S.finite(p.x,10000) and S.finite(p.y,10000)
        and S.finite(p.z,10000) and S.finite(p.heading,36000)
end
local function mode(value) return value=='a_to_b' or value=='b_to_a' or value=='both' end
local function copyPoint(p)
    return p and {x=p.x,y=p.y,z=p.z,heading=p.heading}
end
local function public(p)
    return {id=p.id,name=p.name,mode=p.mode,a=copyPoint(p.a),b=copyPoint(p.b),revision=p.revision,bucket=p.bucket}
end
function S.sendTeleporters(src)
    if not ready then return end
    local state={}
    for id,p in pairs(points) do if p.bucket==GetPlayerRoutingBucket(src) then state[id]=public(p) end end
    TriggerClientEvent(prefix..'state',src,state,GetPlayerRoutingBucket(src))
end
local function publish()
    for _,src in ipairs(GetPlayers()) do S.sendTeleporters(tonumber(src)) end
end
MySQL.ready(function()
    local ok,rows=pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS ptech_omnite_teleporters (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                owner VARCHAR(64) NOT NULL, payload LONGTEXT NOT NULL,
                bucket INT NOT NULL DEFAULT 0, revision INT NOT NULL DEFAULT 1,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        return MySQL.query.await('SELECT * FROM ptech_omnite_teleporters')
    end)
    if not ok or type(rows)~='table' then print('[Toolbox] テレポーターDB初期化失敗。') return end
    points={}
    for _,row in ipairs(rows) do
        local decoded,p=pcall(json.decode,row.payload)
        if decoded and type(p)=='table' and label(p.name) and mode(p.mode) and endpoint(p.a) and endpoint(p.b) then
            p.id,p.owner,p.bucket,p.revision=tostring(row.id),row.owner,tonumber(row.bucket) or 0,tonumber(row.revision) or 1
            points[p.id]=p
        else print(('[Toolbox] 不正なテレポーターをスキップ: %s'):format(row.id)) end
    end
    ready=true publish()
end)

lib.callback.register(prefix..'list',function(src)
    if not ready then return fail('テレポーターDBの準備ができていません。') end
    local result={}
    for id,p in pairs(points) do if p.bucket==GetPlayerRoutingBucket(src) then result[id]=public(p) end end
    return {ok=true,points=result,bucket=GetPlayerRoutingBucket(src)}
end)
local function rate(src)
    local now=GetGameTimer()
    if requests[src] and now-requests[src]<300 then return false end
    requests[src]=now return true
end
lib.callback.register(prefix..'begin',function(src,id,revision)
    local owner,err=authorize(src)
    if not owner then return err end
    if not rate(src) then return fail('少し待ってから操作してください。') end
    local p=id and points[tostring(id)]
    if id and (not p or p.revision~=revision or p.bucket~=GetPlayerRoutingBucket(src)) then
        return fail('登録情報が更新されています。一覧を開き直してください。')
    end
    nextDraft=nextDraft+1
    local draft={token=nextDraft,id=p and p.id,revision=p and p.revision,bucket=GetPlayerRoutingBucket(src),
        a=p and copyPoint(p.a),b=p and copyPoint(p.b),expires=GetGameTimer()+Config.Teleporters.draftLifetime}
    drafts[src]=draft
    return {ok=true,token=draft.token,a=copyPoint(draft.a),b=copyPoint(draft.b),name=p and p.name or '',mode=p and p.mode or 'both'}
end)
local function draftFor(src,token)
    local d=drafts[src]
    if not d or d.token~=token or d.expires<GetGameTimer() or d.bucket~=GetPlayerRoutingBucket(src) then return end
    return d
end
lib.callback.register(prefix..'capture',function(src,token,side)
    local owner,err=authorize(src)
    if not owner then return err end
    local d=draftFor(src,token)
    if not d or (side~='a' and side~='b') then return fail('設置を開き直してください。') end
    local ped=GetPlayerPed(src)
    if ped==0 or GetEntityHealth(ped)<=0 or GetVehiclePedIsIn(ped,false)~=0 or S.hasSeat(src) then
        return fail('徒歩で立った状態で指定してください。')
    end
    local c=GetEntityCoords(ped)
    local p={x=c.x,y=c.y,z=c.z,heading=GetEntityHeading(ped)%360}
    if not endpoint(p) then return fail('現在地を取得できません。') end
    d[side]=p
    return {ok=true,point=copyPoint(p)}
end)
lib.callback.register(prefix..'save',function(src,token,name,direction)
    local owner,err=authorize(src)
    if not owner then return err end
    if not rate(src) then return fail('少し待ってから操作してください。') end
    local d=draftFor(src,token)
    if not d or not endpoint(d.a) or not endpoint(d.b) or not label(name) or not mode(direction) then
        return fail('名前・通行方向・AとBの2地点を指定してください。')
    end
    local dx,dy,dz=d.a.x-d.b.x,d.a.y-d.b.y,d.a.z-d.b.z
    if dx*dx+dy*dy+dz*dz<1 then return fail('AとBは1m以上離して指定してください。') end
    local existing=d.id and points[d.id]
    if d.id and (not existing or existing.revision~=d.revision) then return fail('他の操作で更新されています。開き直してください。') end
    local total,owned=0,0
    for _,p in pairs(points) do total=total+1 if p.owner==owner then owned=owned+1 end end
    if not existing and (total>=Config.Teleporters.maxTotal or owned>=Config.Teleporters.maxPerOwner) then return fail('登録上限に達しています。') end
    local lock=d.id or '__create'
    if locks[lock] then return fail('保存処理中です。') end
    locks[lock]=true
    local p={name=name,mode=direction,a=copyPoint(d.a),b=copyPoint(d.b),bucket=d.bucket,
        owner=existing and existing.owner or owner,revision=existing and existing.revision+1 or 1}
    local id=d.id
    local ok,result=pcall(function()
        if existing then
            return MySQL.update.await('UPDATE ptech_omnite_teleporters SET payload=?,revision=revision+1 WHERE id=? AND revision=?',
                {json.encode(p),id,d.revision})==1
        end
        local inserted=MySQL.insert.await('INSERT INTO ptech_omnite_teleporters (owner,payload,bucket) VALUES (?,?,?)',
            {p.owner,json.encode(p),p.bucket})
        if inserted then id=tostring(inserted) return true end
        return false
    end)
    locks[lock]=nil
    if not ok or not result then return fail('DBに保存できませんでした。もう一度お試しください。') end
    p.id=id points[id]=p
    if drafts[src]==d then drafts[src]=nil end
    publish()
    return {ok=true,id=id}
end)
lib.callback.register(prefix..'delete',function(src,id,revision)
    local owner,err=authorize(src)
    if not owner then return err end
    if not rate(src) then return fail('少し待ってから操作してください。') end
    id=tostring(id)
    local p=points[id]
    if not p or p.revision~=revision or p.bucket~=GetPlayerRoutingBucket(src) then return fail('登録情報が更新されています。') end
    if locks[id] then return fail('保存処理中です。') end
    locks[id]=true
    local ok,n=pcall(MySQL.update.await,'DELETE FROM ptech_omnite_teleporters WHERE id=? AND revision=?',{id,revision})
    locks[id]=nil
    if not ok or n~=1 then return fail('DBから削除できませんでした。') end
    points[id]=nil publish()
    return {ok=true}
end)
lib.callback.register(prefix..'use',function(src,id,side,revision)
    local p=points[tostring(id)]
    if not ready or not p or locks[tostring(id)] or p.revision~=revision or p.bucket~=GetPlayerRoutingBucket(src)
        or (side~='a' and side~='b') then return fail('このテレポーターは利用できません。') end
    if (side=='a' and p.mode=='b_to_a') or (side=='b' and p.mode=='a_to_b') then return fail('こちら側は出口専用です。') end
    local ped=GetPlayerPed(src)
    local data=player(src)
    local metadata=data and data.metadata or {}
    local state=Player(src).state
    if not data or ped==0 or GetEntityHealth(ped)<=0 or GetVehiclePedIsIn(ped,false)~=0 or S.hasSeat(src)
        or metadata.isdead or metadata.inlaststand or metadata.ishandcuffed
        or state.emsEscortedBy or state.emsEscorting then return fail('徒歩で移動できる状態で利用してください。') end
    if not S.near(src,p[side],Config.Teleporters.interactDistance+0.5) then return fail('入口に近づいてください。') end
    local now=GetGameTimer()
    if uses[src] and now-uses[src]<Config.Teleporters.cooldown then return fail('少し待ってから利用してください。') end
    uses[src]=now
    return {ok=true,destination=copyPoint(p[side=='a' and 'b' or 'a'])}
end)
RegisterNetEvent(prefix..'cancel',function(token)
    if drafts[source] and drafts[source].token==token then drafts[source]=nil end
end)
AddEventHandler('playerDropped',function()
    drafts[source],requests[source],uses[source]=nil,nil,nil
end)

local csvHeaders={'id','name','mode','ax','ay','az','ah','bx','by','bz','bh','bucket'}
lib.callback.register(prefix..'csv',function(src,action,input)
    local owner,err=authorize(src) if not owner then return err end
    if action=='export' then
        local rows={}
        for id,p in pairs(points) do if p.bucket==GetPlayerRoutingBucket(src) then
            rows[#rows+1]={id=id,name=p.name,mode=p.mode,ax=p.a.x,ay=p.a.y,az=p.a.z,ah=p.a.heading,
                bx=p.b.x,by=p.b.y,bz=p.b.z,bh=p.b.heading,bucket=p.bucket}
        end end
        table.sort(rows,function(a,b) return tonumber(a.id)<tonumber(b.id) end)
        local text=OmniteCsv.encode(csvHeaders,rows)
        local filename='exports/teleport_'..GetPlayerRoutingBucket(src)..'.csv'
        if SaveResourceFile then assert(SaveResourceFile(GetCurrentResourceName(),filename,text,-1),'CSVを書き出せませんでした。') end
        return {ok=true,text=text,filename=filename}
    end
    if action~='import' then return fail('操作が不正です。') end
    for _ in pairs(locks) do return fail('保存中です。') end
    for src,draft in pairs(drafts) do if draft.expires<GetGameTimer() then drafts[src]=nil else return fail('編集中のテレポーターがあります。編集を閉じてください。') end end
    local ok,result=pcall(function()
        local rows=OmniteCsv.decode(input,csvHeaders)
        assert(#rows>0,'CSVにデータがありません。')
        local prepared,ids,queries={},{},{}
        local total=0 for _ in pairs(points) do total=total+1 end
        for _,r in ipairs(rows) do
            assert(r.id:match('^[1-9]%d*$') and tonumber(r.id)<9007199254740991 and not ids[r.id],'IDが不正または重複しています。') ids[r.id]=true
            local old=points[r.id]
            assert(tonumber(r.bucket)==GetPlayerRoutingBucket(src) and (not old or old.bucket==tonumber(r.bucket)),'現在のバケットと違います。')
            local p={id=r.id,name=r.name,mode=r.mode,a={x=tonumber(r.ax),y=tonumber(r.ay),z=tonumber(r.az),heading=tonumber(r.ah)},
                b={x=tonumber(r.bx),y=tonumber(r.by),z=tonumber(r.bz),heading=tonumber(r.bh)},bucket=tonumber(r.bucket),owner=old and old.owner or owner,revision=old and old.revision+1 or 1}
            assert(label(p.name) and mode(p.mode) and endpoint(p.a) and endpoint(p.b),'設定値が不正です。')
            assert((p.a.x-p.b.x)^2+(p.a.y-p.b.y)^2+(p.a.z-p.b.z)^2>=1,'A・Bは1m以上離してください。')
            if not old then total=total+1 end assert(total<=Config.Teleporters.maxTotal,'登録上限です。')
            prepared[#prepared+1]=p
            queries[#queries+1]={query='INSERT INTO ptech_omnite_teleporters (id,owner,payload,bucket,revision) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE payload=VALUES(payload),revision=revision+1',values={p.id,p.owner,json.encode(p),p.bucket,p.revision}}
        end
        for id in pairs(ids) do locks[id]=true end locks.__create=true
        local executed,committed=pcall(MySQL.transaction.await,queries)
        for id in pairs(ids) do locks[id]=nil end locks.__create=nil
        assert(executed and committed,'CSVのDB保存に失敗しました。')
        for _,p in ipairs(prepared) do points[p.id]=p end publish()
        return {ok=true,count=#prepared}
    end)
    return ok and result or fail(tostring(result))
end)
