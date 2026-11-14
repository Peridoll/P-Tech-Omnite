SeatingServer = { placed = {}, ready = false, mutating = {} }
local S = SeatingServer
local occupied, players, lastRequest = {}, {}, {}

function S.notify(src, text)
    TriggerClientEvent('ptech_omnite_seating:client:notify', src, text)
end

function S.finite(value, limit)
    return type(value) == 'number' and value == value and math.abs(value) <= limit
end

function S.near(src, coords, distance)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - vec3(coords.x, coords.y, coords.z)) <= distance
end

local function stateFor(bucket)
    local state = {}
    for _, entry in pairs(occupied) do
        if entry.bucket == bucket then state[entry.key] = entry.source end
    end
    return state
end

local function publish(bucket)
    local state = stateFor(bucket)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if GetPlayerRoutingBucket(src) == bucket then
            TriggerClientEvent('ptech_omnite_seating:client:syncSeats', src, state)
        end
    end
end

function S.release(src)
    local entry = players[src]
    if not entry then return end
    occupied[entry.lock], players[src] = nil, nil
    TriggerClientEvent('ptech_omnite_seating:client:releaseSeat', src, entry.key)
    publish(entry.bucket)
end

function S.isOccupied(key, bucket)
    return occupied[tostring(bucket) .. ':' .. key] ~= nil
end

function S.positionOccupied(coords, bucket)
    for _, entry in pairs(occupied) do
        if entry.bucket == bucket and #(entry.coords - vec3(coords.x,coords.y,coords.z)) < 0.45 then return true end
    end
    return false
end

function S.resolve(request)
    if type(request) ~= 'table' or type(request.key) ~= 'string' or #request.key > 160 then return end
    local id = request.key:match('^db:(%d+)$')
    if id then
        if S.mutating[id] then return end
        local seat = S.placed[id]
        if seat then return seat.coords, seat.bucket, seat.kind end
        return
    end
    for _, seat in ipairs(Config.FixedSeats) do
        if request.key == 'fixed:' .. seat.id then return seat.coords, seat.bucket or 0, seat.kind or 'chair' end
    end
    -- マップpropはサーバーにentityがないため登録モデル・位置・決定的なキーを検証する。
    local model, x, y, z = request.key:match('^prop:(%-?%d+):(%-?[%d.]+):(%-?[%d.]+):(%-?[%d.]+)$')
    model, x, y, z = tonumber(model), tonumber(x), tonumber(y), tonumber(z)
    if not model or not S.finite(x, 10000) or not S.finite(y, 10000) or not S.finite(z, 10000) then return end
    local known = false
    for name in pairs(Config.ChairModels) do if joaat(name) == model then known = true break end end
    if not known or request.key ~= ('prop:%d:%.3f:%.3f:%.3f'):format(model, x, y, z) then return end
    return vec3(x, y, z), nil, 'chair'
end

RegisterNetEvent('ptech_omnite_seating:server:requestState', function()
    local src = source
    TriggerClientEvent('ptech_omnite_seating:client:syncSeats', src, stateFor(GetPlayerRoutingBucket(src)))
    if S.ready and S.sendPlacements then S.sendPlacements(src) end
end)

function S.claim(src, request)
    local coords, bucket, kind = S.resolve(request)
    if not coords then return false, 'unavailable' end
    local key = request.key
    local function reject(reason)
        return false, reason
    end
    local currentBucket = GetPlayerRoutingBucket(src)
    if bucket and bucket ~= currentBucket then return reject('too_far') end
    if not S.near(src, coords, Config.Seating.serverDistance) then return reject('too_far') end
    if kind == 'patient_bed' and GetResourceState(Config.Placement.medicalResource) ~= 'started' then return reject('unavailable') end
    if players[src] then return reject('already_seated') end
    for _, mutation in pairs(S.mutating) do
        if type(mutation) == 'table' and mutation.bucket == currentBucket then
            for _, point in ipairs(mutation.points) do
                if #(vec3(coords.x,coords.y,coords.z) - vec3(point.x,point.y,point.z)) < 0.45 then return reject('unavailable') end
            end
        end
    end
    for _, entry in pairs(occupied) do
        if entry.bucket == currentBucket and (entry.key == key or #(entry.coords - vec3(coords.x, coords.y, coords.z)) < 0.45) then
            return reject('occupied')
        end
    end
    local lock = tostring(currentBucket) .. ':' .. key
    local entry = { key = key, lock = lock, source = src, bucket = currentBucket, coords = vec3(coords.x, coords.y, coords.z) }
    occupied[lock], players[src] = entry, entry
    publish(currentBucket)
    return true
end

RegisterNetEvent('ptech_omnite_seating:server:trySit', function(request)
    local src = source
    local now = GetGameTimer()
    if lastRequest[src] and now - lastRequest[src] < 300 then return end
    lastRequest[src] = now
    local ok, reason = S.claim(src, request)
    if type(request) == 'table' and type(request.key) == 'string' and #request.key <= 160 then
        TriggerClientEvent('ptech_omnite_seating:client:sitResult', src, ok, request.key, reason)
    end
end)

RegisterNetEvent('ptech_omnite_seating:server:stand', function(key)
    local src = source
    if players[src] and (not key or players[src].key == key) then S.release(src) end
end)

AddEventHandler('playerDropped', function()
    S.release(source)
    lastRequest[source] = nil
end)

CreateThread(function()
    local buckets = {}
    while true do
        Wait(2000)
        for src, entry in pairs(players) do
            if GetPlayerRoutingBucket(src) ~= entry.bucket or not S.near(src, entry.coords, 6.0) then S.release(src) end
        end
        for _, value in ipairs(GetPlayers()) do
            local src = tonumber(value)
            local bucket = GetPlayerRoutingBucket(src)
            if buckets[src] ~= bucket then
                buckets[src] = bucket
                TriggerClientEvent('ptech_omnite_seating:client:syncSeats', src, stateFor(bucket))
                if S.ready and S.sendPlacements then S.sendPlacements(src) end
            end
        end
        for src in pairs(buckets) do if GetPlayerPed(src) == 0 then buckets[src] = nil end end
    end
end)

local function toolCommand(command, event, enabled)
    if enabled == false then return end
    RegisterCommand(command, function(src, args)
        if src ~= 0 then TriggerClientEvent('ptech_omnite_seating:client:' .. event, src, args) end
    end, true)
end
toolCommand(Config.SeatDebug.command, 'toggleDebug')
toolCommand(Config.SeatDebug.ghostCommand, 'toggleGhost')
toolCommand(Config.SeatRecorder.command, 'recordSeat', Config.SeatRecorder.enabled)
toolCommand(Config.SeatRecorder.setupCommand, 'setupSeat', Config.SeatRecorder.enabled)

exports('GetPatientBeds', function()
    local beds = {}
    for id, seat in pairs(S.placed) do
        if seat.kind == 'patient_bed' then beds[id] = json.decode(json.encode(seat)) end
    end
    for _, seat in ipairs(Config.FixedSeats) do
        if seat.kind == 'patient_bed' then beds['fixed:' .. seat.id] = json.decode(json.encode(seat)) end
    end
    return beds
end)
