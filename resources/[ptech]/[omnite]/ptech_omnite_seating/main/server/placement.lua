local S = SeatingServer
local prefix = 'ptech_omnite_seating:'
local busy, cooldown = S.mutating, {}

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

local function permitted(src, seat, owner)
    if seat.owner ~= owner and not admin(src) then return false end
    return seat.kind ~= 'patient_bed' or (isEms(src) and GetResourceState(Config.Placement.medicalResource) == 'started')
end

function S.sendPlacements(src)
    local bucket, state = GetPlayerRoutingBucket(src), {}
    for id, seat in pairs(S.placed) do if seat.bucket == bucket then state[id] = seat end end
    TriggerClientEvent(prefix .. 'client:placements', src, state, bucket)
end

local function publish()
    for _, id in ipairs(GetPlayers()) do S.sendPlacements(tonumber(id)) end
    TriggerEvent(prefix .. 'server:patientBedsChanged')
end

local function validName(value, max)
    return type(value) == 'string' and #value >= 1 and #value <= max and value:match('^[%w_-]+$') ~= nil
end

local function normalize(data)
    if type(data) ~= 'table' or not validName(data.mlo, 64) or not validName(data.name, 64) then return end
    if data.kind ~= 'chair' and data.kind ~= 'bed' and data.kind ~= 'patient_bed' then return end
    local c = data.coords
    if type(c) ~= 'table' or not S.finite(c.x, 10000) or not S.finite(c.y, 10000) or not S.finite(c.z, 10000)
        or not S.finite(data.heading, 36000) then return end
    local style = data.kind == 'chair' and (data.style or Config.Seating.defaultStyle) or Config.Seating.defaultStyle
    local found = data.kind ~= 'chair'
    for _, entry in ipairs(Config.Seating.styles) do if entry.id == style then found = true end end
    if not found then return end
    return { mlo = data.mlo, name = data.name, kind = data.kind, coords = { x = c.x, y = c.y, z = c.z },
        heading = data.heading % 360, style = style }
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
        return MySQL.query.await('SELECT * FROM ptech_omnite_seating')
    end)
    if not ok or type(rows) ~= 'table' then print('[Seating] DB初期化失敗。配置機能は停止しています。') return end
    for _, row in ipairs(rows) do
        local decoded, data = pcall(json.decode, row.payload)
        local seat = decoded and normalize(data)
        if seat then
            seat.id, seat.owner, seat.bucket, seat.revision = tostring(row.id), row.owner, tonumber(row.bucket) or 0, tonumber(row.revision) or 1
            S.placed[seat.id] = seat
        else print(('[Seating] 不正な保存データをスキップ: %s'):format(row.id)) end
    end
    S.ready = true
    publish()
end)

lib.callback.register(prefix .. 'tool', function(src)
    local owner, err = authorize(src)
    if not owner then return err end
    return { ok = true, ems = isEms(src) and GetResourceState(Config.Placement.medicalResource) == 'started', admin = admin(src), owner = owner }
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
    if id and (not existing or existing.revision ~= input.revision or not permitted(src, existing, owner)) then
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
        lines[#lines+1] = ("    { id = 'db_%s', mlo = '%s', name = '%s', kind = '%s', coords = vec3(%.6f, %.6f, %.6f), heading = %.3f, bucket = %d, styles = { '%s' } },")
            :format(seat.id, seat.mlo, seat.name, seat.kind, seat.coords.x, seat.coords.y, seat.coords.z, seat.heading, seat.bucket, seat.style)
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
        local owner = authorize(inventory.id)
        if not owner then return false end
    end
end)

-- consume=0ではserver.exportのusedItemが呼ばれないため、利用完了イベントを使う。
AddEventHandler('ox_inventory:usedItem', function(src, name)
    if name ~= Config.Placement.item then return end
    local owner = authorize(src)
    if owner then TriggerClientEvent(prefix .. 'client:openPlacement', src) end
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
    TriggerClientEvent(prefix .. 'client:patientBed', patient, bed, key)
    return {ok=true}
end

lib.callback.register(prefix .. 'placePatient', function(src, patient, id) return placePatient(src,patient,id) end)
exports('PlacePatientInBed', function(actor,patient,id)
    if GetInvokingResource() ~= Config.Placement.medicalResource then return fail('Mediora専用の連携口です。') end
    return placePatient(actor,patient,id)
end)
