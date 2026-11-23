local S = SeatingServer
local prefix = 'ptech_omnite_seating:'
local busy, cooldown = S.mutating, {}
local mlos = {}

local function playerData(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData
end

local function hasTool(src)
    return (exports.ox_inventory:GetItemCount(src, Config.Placement.item) or 0) > 0
end

local function isEms(src)
    local data = playerData(src)
    return data and data.job and Config.Placement.emsJobs[data.job.name] == true
end

local function admin(src) return IsPlayerAceAllowed(src, Config.Placement.adminAce) end
local function fail(text) return { ok = false, message = text } end

local function authorize(src)
    if not S.ready then return nil, fail('座席DBの準備ができていません。') end
    local data = playerData(src)
    if not data or not hasTool(src) then return nil, fail('設定ツールを所持していません。') end
    return data.citizenid
end

local function permitted(src, seat, owner, action)
    local shared = (action=='save' and Config.Placement.editByToolHolder)
        or (action=='delete' and Config.Placement.deleteByToolHolder)
    if seat.owner ~= owner and not admin(src) and not shared then return false end
    return seat.kind ~= 'patient_bed' or (isEms(src) and GetResourceState(Config.Placement.medicalResource) == 'started')
end

function S.sendPlacements(src)
    local bucket, state = GetPlayerRoutingBucket(src), {}
    for id, seat in pairs(S.placed) do if seat.bucket == bucket then state[id] = seat end end
    TriggerClientEvent(prefix .. 'client:placements', src, state, bucket)
    if S.sendTeleporters then S.sendTeleporters(src) end
end

local function publish()
    for _, id in ipairs(GetPlayers()) do S.sendPlacements(tonumber(id)) end
    TriggerEvent(prefix .. 'server:patientBedsChanged')
end

local function validName(value, max)
    return type(value) == 'string' and #value >= 1 and #value <= max and value:match('^[%w_-]+$') ~= nil
end

local function validLabel(value)
    if type(value)~='string' or value:find('%c') then return false end
    local length=utf8.len(value)
    return length and length>=1 and length<=64 and value:match('%S')~=nil
end

local function mloList()
    local result,seen={},{}
    for id,entry in pairs(mlos) do result[#result+1]={id=id,label=entry.label} seen[id]=true end
    for _,seat in pairs(S.placed) do
        if not seen[seat.mlo] then result[#result+1]={id=seat.mlo,label=seat.mlo} seen[seat.mlo]=true end
    end
    for _,seat in ipairs(Config.FixedSeats) do
        if seat.mlo and not seen[seat.mlo] then result[#result+1]={id=seat.mlo,label=seat.mloLabel or seat.mlo} seen[seat.mlo]=true end
    end
    table.sort(result,function(a,b) return a.label<b.label end)
    return result
end

local function normalize(data)
    if type(data) ~= 'table' or not validName(data.mlo, 64) or not validLabel(data.name) then return end
    if data.group and not validName(data.group,64) then return end
    if not Config.Seating.kindStyles[data.kind] then return end
    local c = data.coords
    if type(c) ~= 'table' or not S.finite(c.x, 10000) or not S.finite(c.y, 10000) or not S.finite(c.z, 10000)
        or not S.finite(data.heading, 36000) then return end
    local style
    if data.style then style=OmniteSeating.styleFor(data.kind,data.style)
    else style=OmniteSeating.stylesFor(data.kind)[1] end
    if not style then return end
    return { mlo = data.mlo, name = data.name, kind = data.kind, coords = { x = c.x, y = c.y, z = c.z },
        heading = data.heading % 360, style = style.id, group=data.group }
end

MySQL.ready(function()
    local ok, rows = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS ptech_omnite_seating (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                owner VARCHAR(64) NOT NULL, mlo VARCHAR(64) NOT NULL,
                name VARCHAR(64) NOT NULL, kind VARCHAR(24) NOT NULL,
                payload LONGTEXT NOT NULL, bucket INT NOT NULL DEFAULT 0,
                revision INT NOT NULL DEFAULT 1,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_mlo (mlo), INDEX idx_owner (owner)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS ptech_omnite_seating_mlos (
                id VARCHAR(64) NOT NULL PRIMARY KEY,
                label VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL UNIQUE,
                owner VARCHAR(64) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        return {seats=MySQL.query.await('SELECT * FROM ptech_omnite_seating'),mlos=MySQL.query.await('SELECT * FROM ptech_omnite_seating_mlos')}
    end)
    if not ok or type(rows) ~= 'table' then print('[Seating] DB初期化失敗。配置機能は停止しています。') return end
    if type(rows.seats)~='table' or type(rows.mlos)~='table' then return end
    mlos={}
    for _,row in ipairs(rows.mlos) do mlos[row.id]={label=row.label,owner=row.owner} end
    for _, row in ipairs(rows.seats) do
        local decoded, data = pcall(json.decode, row.payload)
        local seat = decoded and normalize(data)
        if seat then
            seat.id, seat.owner, seat.bucket, seat.revision = tostring(row.id), row.owner, tonumber(row.bucket) or 0, tonumber(row.revision) or 1
            seat.group=seat.group or ('furniture_'..seat.id)
            S.placed[seat.id] = seat
        else print(('[Seating] 不正な保存データをスキップ: %s'):format(row.id)) end
    end
    S.ready = true
    publish()
end)

lib.callback.register(prefix .. 'tool', function(src)
    local owner, err = authorize(src)
    if not owner then return err end
    return { ok = true, ems = isEms(src) and GetResourceState(Config.Placement.medicalResource) == 'started', admin = admin(src), owner = owner, mlos=mloList() }
end)

lib.callback.register(prefix .. 'registerMlo',function(src,label)
    local owner,err=authorize(src)
    if not owner then return err end
    if type(label)~='string' then return fail('MLO名を入力してください。') end
    label=label:match('^%s*(.-)%s*$')
    if not validLabel(label) then return fail('MLO名は1〜64文字で入力してください。') end
    local existingId
    for _,entry in ipairs(mloList()) do
        if entry.label==label then
            if mlos[entry.id] then return {ok=true,id=entry.id,mlos=mloList()} end
            existingId=entry.id break
        end
    end
    if busy.__mlo then return fail('MLO登録中です。少し待ってから操作してください。') end
    busy.__mlo=true
    local id=existingId or ('mlo_%d_%06d'):format(os.time(),math.random(0,999999))
    local ok,result=pcall(MySQL.update.await,'INSERT INTO ptech_omnite_seating_mlos (id,label,owner) VALUES (?,?,?)',{id,label,owner})
    busy.__mlo=nil
    if not ok or result~=1 then return fail('MLO名を保存できませんでした。もう一度お試しください。') end
    mlos[id]={label=label,owner=owner}
    return {ok=true,id=id,mlos=mloList()}
end)

local function mutate(src, action, input)
    local owner, err = authorize(src)
    if not owner then return err end
    if type(input) ~= 'table' then return fail('入力が不正です。') end
    local now = GetGameTimer()
    if cooldown[src] and now - cooldown[src] < 500 then return fail('少し待ってから操作してください。') end
    cooldown[src] = now
    local id = input.id and tostring(input.id)
    local existing = id and S.placed[id]
    local lock = id or '__create'
    if busy[lock] then return fail('保存処理中です。') end
    if id and (not existing or existing.revision ~= input.revision or not permitted(src, existing, owner, action)) then
        return fail('変更権限がないか、他の操作で更新されています。一覧を開き直してください。')
    end
    if existing and (existing.bucket ~= GetPlayerRoutingBucket(src) or not S.near(src, existing.coords, Config.Placement.maxDistance)
        or S.positionOccupied(existing.coords, existing.bucket)) then return fail('近くの空席だけ変更できます。') end
    local seat
    if action == 'save' then
        seat = normalize(input)
        if not seat or not S.near(src, seat.coords, Config.Placement.maxDistance) then return fail('配置データまたは距離が不正です。') end
        if seat.kind == 'patient_bed' and (not isEms(src) or GetResourceState(Config.Placement.medicalResource) ~= 'started') then
            return fail('患者用ベッドの設置はMediora起動中のEMSのみ可能です。')
        end
        local total, owned = 0, 0
        for _, placed in pairs(S.placed) do total = total + 1 if placed.owner == owner then owned = owned + 1 end end
        if not existing and (owned >= Config.Placement.maxPerOwner or total >= Config.Placement.maxTotal) then return fail('登録上限に達しています。') end
        seat.owner, seat.bucket = existing and existing.owner or owner, GetPlayerRoutingBucket(src)
        local group=input.group or (existing and existing.group)
        if group then
            local anchor,count=nil,0
            for _,placed in pairs(S.placed) do
                if placed.group==group then
                    if not anchor or tonumber(placed.id)<tonumber(anchor.id) then anchor=placed end
                    count=count+1
                end
            end
            if not anchor or (not existing and anchor.owner~=owner and not admin(src)) or anchor.mlo~=seat.mlo or anchor.bucket~=seat.bucket then
                return fail('この家具グループには追加できません。')
            end
            if not existing and count>=Config.Placement.maxPerGroup then return fail('この家具の利用地点数が上限に達しています。') end
            if #(vec3(seat.coords.x,seat.coords.y,seat.coords.z)-vec3(anchor.coords.x,anchor.coords.y,anchor.coords.z))>Config.Placement.groupDistance then
                return fail('同じ家具グループの地点の近くに配置してください。')
            end
            seat.owner=existing and existing.owner or anchor.owner
            seat.group=group
        else seat.group=('furniture_%d_%06d'):format(os.time(),math.random(0,999999)) end
        seat.revision = existing and existing.revision + 1 or 1
    elseif not existing then return fail('削除する座席がありません。') end
    local points = {}
    if existing then points[#points+1] = existing.coords end
    if seat then points[#points+1] = seat.coords end
    busy[lock] = { bucket = GetPlayerRoutingBucket(src), points = points }
    local ok, result = pcall(function()
        if action == 'delete' then
            return MySQL.update.await('DELETE FROM ptech_omnite_seating WHERE id = ? AND revision = ?', { id, existing.revision }) == 1
        elseif existing then
            return MySQL.update.await('UPDATE ptech_omnite_seating SET mlo=?, name=?, kind=?, payload=?, revision=revision+1 WHERE id=? AND revision=?',
                { seat.mlo, seat.name, seat.kind, json.encode(seat), id, existing.revision }) == 1
        else
            local inserted = MySQL.insert.await('INSERT INTO ptech_omnite_seating (owner,mlo,name,kind,payload,bucket) VALUES (?,?,?,?,?,?)',
                { seat.owner, seat.mlo, seat.name, seat.kind, json.encode(seat), seat.bucket })
            if inserted then id = tostring(inserted) return true end
            return false
        end
    end)
    busy[lock] = nil
    if not ok or not result then return fail('DB保存に失敗しました。変更は反映されていません。') end
    if action == 'delete' then S.placed[id] = nil else seat.id = id S.placed[id] = seat end
    publish()
    return { ok = true, id = id }
end

lib.callback.register(prefix .. 'save', function(src, input) return mutate(src, 'save', input) end)
lib.callback.register(prefix .. 'delete', function(src, input) return mutate(src, 'delete', input) end)

lib.callback.register(prefix .. 'export', function(src, mlo)
    if not admin(src) then return fail('管理者のみ出力できます。') end
    if not S.ready then return fail('DBの準備ができていません。') end
    if mlo ~= nil and not validName(mlo, 64) then return fail('MLO名が不正です。') end
    local entries = {}
    for _, seat in pairs(S.placed) do if not mlo or seat.mlo == mlo then entries[#entries + 1] = seat end end
    table.sort(entries, function(a,b) return tonumber(a.id) < tonumber(b.id) end)
    local lines = { '-- DBを残す場合は同じ席をConfigへ二重登録しないでください。', 'Config.FixedSeats = {' }
    for _, seat in ipairs(entries) do
        local label=mlos[seat.mlo] and mlos[seat.mlo].label or seat.mlo
        lines[#lines+1] = ("    { id = 'db_%s', mlo = '%s', mloLabel = %q, name = %q, kind = '%s', group = %q, coords = vec3(%.6f, %.6f, %.6f), heading = %.3f, bucket = %d, style = '%s' },")
            :format(seat.id, seat.mlo, label, seat.name, seat.kind, seat.group or ('furniture_'..seat.id), seat.coords.x, seat.coords.y, seat.coords.z, seat.heading, seat.bucket, seat.style)
    end
    lines[#lines+1] = '}'
    return { ok = true, text = table.concat(lines, '\n') }
end)

RegisterCommand('omnite_seatgive', function(src, args)
    if src ~= 0 and not admin(src) then return end
    local target = tonumber(args[1])
    if not target or GetPlayerPed(target) == 0 then return end
    local ok = exports.ox_inventory:AddItem(target, Config.Placement.item, 1)
    if src ~= 0 then S.notify(src, ok and '設定ツールを配布しました。' or '配布できませんでした。') end
end, false)

exports('usePlacementTool', function(event, item, inventory)
    if event == 'usingItem' then
        local owner, err = authorize(inventory.id)
        if not owner then S.notify(inventory.id, err.message) return false end
    end
end)

AddEventHandler('playerDropped', function() cooldown[source] = nil end)

-- Mediora側からも同じ権限・距離・占有検証を通して患者を移せる。
local function placePatient(actor, patient, id)
    actor, patient = tonumber(actor), tonumber(patient)
    local bed = S.placed[tostring(id)]
    local key = bed and ('db:' .. bed.id)
    if not bed and type(id) == 'string' then
        for _, configured in ipairs(Config.FixedSeats) do
            if id == 'fixed:' .. configured.id and configured.kind == 'patient_bed' then
                bed = {id=id,kind=configured.kind,coords=configured.coords,heading=configured.heading or 0,bucket=configured.bucket or 0}
                key = id
                break
            end
        end
    end
    if not actor or not patient or not S.ready or not bed or bed.kind ~= 'patient_bed'
        or not isEms(actor) or GetResourceState(Config.Placement.medicalResource) ~= 'started' then
        return fail('患者用ベッドはMediora起動中のEMSのみ使用できます。')
    end
    local bucket = GetPlayerRoutingBucket(actor)
    if GetPlayerPed(patient) == 0 or bucket ~= bed.bucket or GetPlayerRoutingBucket(patient) ~= bucket
        or not S.near(actor, bed.coords, Config.Seating.serverDistance)
        or not S.near(patient, bed.coords, Config.Seating.serverDistance) then return fail('患者とベッドの近くで操作してください。') end
    local ok = S.claim(patient, {key=key})
    if not ok then return fail('患者またはベッドが使用中です。') end
    if GetResourceState('ptech_mediora_escort') == 'started' then
        local released, allowed = pcall(function()
            return exports.ptech_mediora_escort:PreparePatientBed(actor, patient)
        end)
        if not released or allowed ~= true then
            S.release(patient)
            return fail('搬送を解除できません。患者の搬送者がベッドへ移してください。')
        end
    end
    TriggerClientEvent(prefix .. 'client:patientBed', patient, bed, key)
    return {ok=true}
end

lib.callback.register(prefix .. 'placePatient', function(src, patient, id) return placePatient(src,patient,id) end)
exports('PlacePatientInBed', function(actor,patient,id)
    if GetInvokingResource() ~= Config.Placement.medicalResource then return fail('Mediora専用の連携口です。') end
    return placePatient(actor,patient,id)
end)
