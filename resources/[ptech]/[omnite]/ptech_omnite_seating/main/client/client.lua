local occupiedSeats = {}
local currentSeat
local pendingSeatKey
local pendingSeat
local setupState
local seatDebugEnabled = false
local seatGhostEnabled = false
local debugObjectCache = {}
local ghostObjectCache = {}
local targetModels = {}
local fixedZoneIds = {}
local chairModelsByHash = {}
local lastStyleId = Config.Seating.defaultStyle

local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function drawSetupHelp(message)
    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandDisplayText(0.5, 0.86)
end

local function drawDebugText(coords, message)
    SetDrawOrigin(coords.x, coords.y, coords.z + 0.35, 0)
    SetTextFont(4)
    SetTextScale(0.28, 0.28)
    SetTextColour(255, 255, 255, 230)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function copyConfigToClipboard(text)
    SendNUIMessage({ action = 'copyText', text = text })
    SetNuiFocus(true, true)
end

local function getStylesForSeat(seat)
    local styles = {}
    local allowedIds = seat and seat.styleIds

    for _, style in ipairs(Config.Seating.styles) do
        local allowed = not allowedIds
        if allowedIds then
            for _, styleId in ipairs(allowedIds) do
                if styleId == style.id then
                    allowed = true
                    break
                end
            end
        end

        if allowed then
            styles[#styles + 1] = style
        end
    end

    return styles
end

local function getStyleForSeat(seat)
    local styles = getStylesForSeat(seat)
    if #styles == 0 then return nil end

    local preferredId = seat.styleId or lastStyleId or Config.Seating.defaultStyle
    for index, style in ipairs(styles) do
        if style.id == preferredId then
            seat.styleId = style.id
            return style, index, styles
        end
    end

    seat.styleId = styles[1].id
    return styles[1], 1, styles
end

local function canStartSitting()
    local ped = PlayerPedId()
    return not currentSeat
        and not pendingSeatKey
        and not setupState
        and not (SeatingClient and SeatingClient.placing)
        and not IsPedInAnyVehicle(ped, false)
        and not IsPedDeadOrDying(ped, true)
        and not IsPedRagdoll(ped)
        and not IsPedCuffed(ped)
end

local function isAvailable(seatKey)
    if not canStartSitting() then return false end
    local owner = occupiedSeats[seatKey]
    return owner == nil or owner == GetPlayerServerId(PlayerId())
end

local function makeSeatKey(model, coords)
    return ('prop:%d:%.3f:%.3f:%.3f'):format(model, coords.x, coords.y, coords.z)
end

local function requestSit(seat)
    if not canStartSitting() then return end
    if not isAvailable(seat.key) then
        notify('この席は使用中です。')
        return
    end

    getStyleForSeat(seat)
    pendingSeatKey = seat.key
    pendingSeat = seat
    TriggerServerEvent('ptech_omnite_seating:server:trySit', {
        key = seat.key,
        coords = { x = seat.lockCoords.x, y = seat.lockCoords.y, z = seat.lockCoords.z },
    })

    SetTimeout(5000, function()
        if pendingSeatKey == seat.key then
            pendingSeatKey = nil
            pendingSeat = nil
            notify('座席を確保できませんでした。')
        end
    end)
end

local function getModelSeat(entity)
    local modelHash = GetEntityModel(entity)
    local modelData = chairModelsByHash[modelHash]
    if not modelData then return nil end

    local objectCoords = GetEntityCoords(entity)
    local config = modelData.config
    local offset = config.offset or vec3(0.0, 0.0, 0.45)
    local sitCoords = GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)

    return {
        key = makeSeatKey(modelHash, objectCoords),
        lockCoords = objectCoords,
        sitCoords = sitCoords,
        heading = (GetEntityHeading(entity) + (config.headingOffset or 180.0)) % 360.0,
        styleIds = config.styles,
    }
end

local function startSeatScenario(seat)
    if seat.kind == 'bed' or seat.kind == 'patient_bed' then
        local anim = Config.Placement.bedAnimation
        local ok = pcall(lib.requestAnimDict, anim.dict, 5000)
        if not ok then notify('ベッドのアニメーションを読み込めませんでした。') return false end
        if currentSeat ~= seat then return false end
        TaskPlayAnimAdvanced(PlayerPedId(), anim.dict, anim.clip,
            seat.sitCoords.x, seat.sitCoords.y, seat.sitCoords.z, 0.0, 0.0, seat.heading,
            8.0, -8.0, -1, 1, 0.0, false, false)
        return true
    end
    local style = getStyleForSeat(seat)
    if not style then
        notify('この席に利用できる着席スタイルがありません。')
        return false
    end

    local ped = PlayerPedId()
    local offset = style.offset or vec3(0.0, 0.0, 0.0)
    local heading = (seat.heading + (style.headingOffset or 0.0)) % 360.0
    local headingRadians = math.rad(seat.heading)
    local forwardX, forwardY = -math.sin(headingRadians), math.cos(headingRadians)
    local rightX, rightY = math.cos(headingRadians), math.sin(headingRadians)
    local sitX = seat.sitCoords.x + rightX * offset.x + forwardX * offset.y
    local sitY = seat.sitCoords.y + rightY * offset.x + forwardY * offset.y
    local sitZ = seat.sitCoords.z + offset.z
    seat.styleId = style.id
    lastStyleId = style.id
    TaskStartScenarioAtPosition(
        ped,
        style.scenario,
        sitX,
        sitY,
        sitZ,
        heading,
        -1,
        true,
        true
    )
    return true
end

local function sitOnSeat(seat)
    seatDebugEnabled, seatGhostEnabled = false, false
    seat.returnCoords = GetEntityCoords(PlayerPedId())
    currentSeat = seat
    pendingSeatKey = nil
    pendingSeat = nil
    if not startSeatScenario(seat) then
        currentSeat = nil
        ClearPedTasks(PlayerPedId())
        TriggerServerEvent('ptech_omnite_seating:server:stand', seat.key)
    end
end

local function cycleSitStyle()
    local seat = currentSeat or setupState
    if not seat then return end
    if seat.kind and seat.kind ~= 'chair' then return end

    local _, currentIndex, styles = getStyleForSeat(seat)
    if not styles or #styles < 2 then
        notify('この席で切り替えられるスタイルはありません。')
        return
    end

    local nextIndex = (currentIndex % #styles) + 1
    seat.styleId = styles[nextIndex].id
    lastStyleId = seat.styleId

    if currentSeat then
        ClearPedTasks(PlayerPedId())
        startSeatScenario(currentSeat)
    elseif setupState then
        ClearPedTasks(PlayerPedId())
        startSeatScenario(setupState)
    end

    notify(('着席スタイル: %s'):format(styles[nextIndex].label))
end

local function standUp()
    if not currentSeat and not pendingSeatKey then return end

    local previous = currentSeat
    local seatKey = currentSeat and currentSeat.key or pendingSeatKey
    pendingSeatKey = nil
    pendingSeat = nil
    currentSeat = nil

    ClearPedTasks(PlayerPedId())
    if previous and previous.kind and previous.kind ~= 'chair' and previous.returnCoords then
        local c = previous.returnCoords
        SetEntityCoordsNoOffset(PlayerPedId(), c.x, c.y, c.z, false, false, false)
    end
    TriggerServerEvent('ptech_omnite_seating:server:stand', seatKey)
end

RegisterCommand('+ptech_omnite_stand', function()
    standUp()
end, false)
RegisterCommand('-ptech_omnite_stand', function() end, false)
RegisterKeyMapping('+ptech_omnite_stand', '立ち上がる', 'keyboard', Config.Seating.standKey)

RegisterCommand('+ptech_omnite_cycle_sit_style', function()
    cycleSitStyle()
end, false)
RegisterCommand('-ptech_omnite_cycle_sit_style', function() end, false)
RegisterKeyMapping('+ptech_omnite_cycle_sit_style', '着席スタイルを切り替える', 'keyboard', Config.Seating.styleKey)

local function validateSeatId(id)
    return type(id) == 'string' and id:match('^[%w_-]+$') ~= nil
end

local function printSeatConfig(id, coords, heading)
    local line = ('    { id = \'%s\', coords = vec3(%.3f, %.3f, %.3f), heading = %.1f, radius = %.2f },')
        :format(id, coords.x, coords.y, coords.z, heading, Config.SeatRecorder.radius or 0.45)
    copyConfigToClipboard(line)
    return line
end

local function recordCurrentSeat(_, args)
    local id = args[1] or ('seat_%d'):format(GetGameTimer())
    if not validateSeatId(id) then
        notify('IDは半角英数字、_、-だけ使えます。')
        return
    end

    local ped = PlayerPedId()
    printSeatConfig(id, GetEntityCoords(ped), GetEntityHeading(ped))
    notify(('座席設定をコピーする画面を開きました: %s'):format(id))
end

local function previewSetupSeat()
    if not setupState then return end
    ClearPedTasks(PlayerPedId())
    startSeatScenario(setupState)
end

local function endSeatSetup(save)
    if not setupState then return end

    local setup = setupState
    setupState = nil
    ClearPedTasks(PlayerPedId())

    if save then
        printSeatConfig(setup.id, setup.sitCoords, setup.heading)
        notify(('座席設定をコピーする画面を開きました: %s'):format(setup.id))
    else
        notify('座席配置をキャンセルしました。')
    end
end

local function beginSeatSetup(_, args)
    if currentSeat or pendingSeatKey or setupState or (SeatingClient and SeatingClient.placing) then
        notify('座っている間は座席配置を開始できません。')
        return
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) then
        notify('車両外で立っているときに実行してください。')
        return
    end

    local id = args[1] or ('seat_%d'):format(GetGameTimer())
    if not validateSeatId(id) then
        notify('IDは半角英数字、_、-だけ使えます。')
        return
    end

    local coords = GetEntityCoords(ped)
    setupState = {
        id = id,
        key = 'setup:' .. id,
        lockCoords = coords,
        sitCoords = coords,
        heading = GetEntityHeading(ped),
        styleId = lastStyleId,
    }
    previewSetupSeat()
    notify('矢印キーで位置、Q/Eで高さ、Z/Cで向きを調整。Enterで保存、Escでキャンセル。')
end

if Config.SeatRecorder.enabled then
    RegisterNetEvent('ptech_omnite_seating:client:recordSeat', function(args) recordCurrentSeat(nil,args) end)
    RegisterNetEvent('ptech_omnite_seating:client:setupSeat', function(args) beginSeatSetup(nil,args) end)
end

local function toggleSeatDebug()
    if currentSeat or pendingSeatKey or setupState or (SeatingClient and SeatingClient.placing) then
        notify('座席配置中・着席中はデバッグモードを切り替えられません。')
        return
    end

    seatDebugEnabled = not seatDebugEnabled
    notify(seatDebugEnabled
        and '座席デバッグ ON: 登録椅子の座席マーカーを表示します。'
        or '座席デバッグ OFF')
end

RegisterNetEvent('ptech_omnite_seating:client:toggleDebug', toggleSeatDebug)

local function toggleSeatGhost()
    if currentSeat or pendingSeatKey or setupState or (SeatingClient and SeatingClient.placing) then
        notify('座席配置中・着席中は貫通モードを切り替えられません。')
        return
    end

    seatGhostEnabled = not seatGhostEnabled
    notify(seatGhostEnabled
        and 'オブジェクト貫通 ON: 近くのオブジェクトを通り抜けます。'
        or 'オブジェクト貫通 OFF')
end

RegisterNetEvent('ptech_omnite_seating:client:toggleGhost', toggleSeatGhost)

RegisterNUICallback('clipboardResult', function(data, cb)
    if data and data.success then
        SetNuiFocus(false, false)
        notify('座席設定をクリップボードにコピーしました。')
    else
        notify('コピーできませんでした。画面の設定行を選択してコピーしてください。')
    end
    cb({ ok = true })
end)

RegisterNUICallback('clipboardCancel', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNetEvent('ptech_omnite_seating:client:sitResult', function(success, seatKey, reason)
    if pendingSeatKey ~= seatKey then
        if success then
            TriggerServerEvent('ptech_omnite_seating:server:stand', seatKey)
        end
        return
    end

    if not success then
        pendingSeatKey = nil
        pendingSeat = nil
        if reason == 'occupied' then
            notify('この席は使用中です。')
        elseif reason == 'already_seated' then
            notify('すでに座っています。')
        elseif reason == 'too_far' then
            notify('椅子に近づいてから座ってください。')
        else
            notify('この席は現在利用できません。')
        end
        return
    end

    local seat = pendingSeat and pendingSeat.key == seatKey and pendingSeat or nil
    pendingSeat = nil
    if not seat then
        TriggerServerEvent('ptech_omnite_seating:server:stand', seatKey)
        return
    end
    sitOnSeat(seat)
end)

RegisterNetEvent('ptech_omnite_seating:client:seatState', function(seatKey, playerId)
    occupiedSeats[seatKey] = playerId
end)

RegisterNetEvent('ptech_omnite_seating:client:syncSeats', function(state)
    occupiedSeats = state or {}
end)

CreateThread(function()
    for modelName, modelConfig in pairs(Config.ChairModels) do
        targetModels[#targetModels + 1] = modelName
        chairModelsByHash[GetHashKey(modelName)] = { name = modelName, config = modelConfig }
    end

    if #targetModels > 0 then
        exports.ox_target:addModel(targetModels, {
            {
                name = 'ptech_omnite_seating:sit',
                label = Config.Seating.targetLabel,
                icon = 'fa-solid fa-chair',
                distance = Config.Seating.targetDistance,
                canInteract = function(entity)
                    local seat = getModelSeat(entity)
                    return seat ~= nil and isAvailable(seat.key)
                end,
                onSelect = function(data)
                    local seat = getModelSeat(data.entity)
                    if seat then requestSit(seat) end
                end,
            },
        })
    end

    for _, fixedSeat in ipairs(Config.FixedSeats) do
        local seat = {
            key = 'fixed:' .. fixedSeat.id,
            lockCoords = fixedSeat.coords,
            sitCoords = fixedSeat.coords,
            heading = fixedSeat.heading or 0.0,
            styleIds = fixedSeat.styles,
            kind = fixedSeat.kind or 'chair',
        }

        local zoneId = exports.ox_target:addSphereZone({
            coords = fixedSeat.coords,
            radius = fixedSeat.radius or 0.45,
            name = 'ptech_omnite_seating:' .. fixedSeat.id,
            options = {
                {
                    name = 'ptech_omnite_seating:fixed:' .. fixedSeat.id,
                    label = fixedSeat.kind and fixedSeat.kind ~= 'chair' and '横になる' or Config.Seating.targetLabel,
                    icon = 'fa-solid fa-chair',
                    distance = Config.Seating.targetDistance,
                    canInteract = function()
                        return isAvailable(seat.key)
                            and (fixedSeat.bucket or 0) == (SeatingClient and SeatingClient.bucket or 0)
                            and (seat.kind ~= 'patient_bed' or GetResourceState(Config.Placement.medicalResource) == 'started')
                    end,
                    onSelect = function()
                        requestSit(seat)
                    end,
                },
                {
                    name = 'ptech_omnite_seating:fixedPatient:' .. fixedSeat.id,
                    label = '患者をベッドへ移す',
                    icon = 'fa-solid fa-user-nurse',
                    distance = Config.Seating.targetDistance,
                    canInteract = function()
                        local player = exports.qbx_core:GetPlayerData()
                        return fixedSeat.kind == 'patient_bed' and (fixedSeat.bucket or 0) == (SeatingClient and SeatingClient.bucket or 0)
                            and GetResourceState(Config.Placement.medicalResource) == 'started'
                            and player and player.job and Config.Placement.emsJobs[player.job.name] == true
                    end,
                    onSelect = function() TriggerEvent('ptech_omnite_seating:client:choosePatient', 'fixed:' .. fixedSeat.id) end,
                },
            },
        })
        fixedZoneIds[#fixedZoneIds + 1] = zoneId
    end

    TriggerServerEvent('ptech_omnite_seating:server:requestState')
end)

SeatingClient = {
    requestSit = requestSit,
    isAvailable = isAvailable,
    canStart = canStartSitting,
    notify = notify,
    copy = copyConfigToClipboard,
    busy = function() return currentSeat or pendingSeatKey or setupState end,
    drawText = drawDebugText,
    debug = function() return seatDebugEnabled end,
    bucket = 0,
}

RegisterNetEvent('ptech_omnite_seating:client:notify', notify)
RegisterNetEvent('ptech_omnite_seating:client:releaseSeat', function(key)
    if currentSeat and currentSeat.key == key then standUp() end
end)
RegisterNetEvent('ptech_omnite_seating:client:patientBed', function(bed, key)
    if not canStartSitting() then
        TriggerServerEvent('ptech_omnite_seating:server:stand', key)
        notify('現在の状態ではベッドを利用できません。')
        return
    end
    sitOnSeat({key=key, kind='patient_bed',
        lockCoords=vec3(bed.coords.x,bed.coords.y,bed.coords.z),
        sitCoords=vec3(bed.coords.x,bed.coords.y,bed.coords.z),heading=bed.heading})
end)
AddEventHandler('QBCore:Client:OnPlayerUnload', standUp)

CreateThread(function()
    local setupControls = { 172, 173, 174, 175, 20, 26, 38, 44, 191, 202, 21 }

    while true do
        if setupState then
            for _, control in ipairs(setupControls) do
                DisableControlAction(0, control, true)
            end

            local ped = PlayerPedId()
            local step = IsDisabledControlPressed(0, 21)
                and Config.SeatRecorder.coarseStep
                or Config.SeatRecorder.fineStep
            local headingRadians = math.rad(setupState.heading)
            local forwardX, forwardY = -math.sin(headingRadians), math.cos(headingRadians)
            local rightX, rightY = math.cos(headingRadians), math.sin(headingRadians)
            local coords = setupState.sitCoords
            local changed = false

            if IsDisabledControlJustPressed(0, 172) then
                setupState.sitCoords = vec3(coords.x + forwardX * step, coords.y + forwardY * step, coords.z)
                changed = true
            elseif IsDisabledControlJustPressed(0, 173) then
                setupState.sitCoords = vec3(coords.x - forwardX * step, coords.y - forwardY * step, coords.z)
                changed = true
            elseif IsDisabledControlJustPressed(0, 174) then
                setupState.sitCoords = vec3(coords.x - rightX * step, coords.y - rightY * step, coords.z)
                changed = true
            elseif IsDisabledControlJustPressed(0, 175) then
                setupState.sitCoords = vec3(coords.x + rightX * step, coords.y + rightY * step, coords.z)
                changed = true
            elseif IsDisabledControlJustPressed(0, 38) then
                setupState.sitCoords = vec3(coords.x, coords.y, coords.z + step)
                changed = true
            elseif IsDisabledControlJustPressed(0, 44) then
                setupState.sitCoords = vec3(coords.x, coords.y, coords.z - step)
                changed = true
            elseif IsDisabledControlJustPressed(0, 20) then
                setupState.heading = (setupState.heading - Config.SeatRecorder.headingStep) % 360.0
                changed = true
            elseif IsDisabledControlJustPressed(0, 26) then
                setupState.heading = (setupState.heading + Config.SeatRecorder.headingStep) % 360.0
                changed = true
            elseif IsDisabledControlJustPressed(0, 191) then
                endSeatSetup(true)
            elseif IsDisabledControlJustPressed(0, 202) then
                endSeatSetup(false)
            end

            if changed then previewSetupSeat() end
            if setupState then
                local style = getStyleForSeat(setupState)
                drawSetupHelp(('配置中: %s | %s\n↑↓前後  ←→左右  E/Q高さ  C/Z向き  Gスタイル  Shiftで粗調整\nEnter 保存 / Esc キャンセル')
                    :format(setupState.id, style and style.label or 'スタイルなし'))
            end
            Wait(0)
        elseif seatDebugEnabled then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local markerDistance = Config.SeatDebug.markerDistance

            for _, entity in ipairs(debugObjectCache) do
                if DoesEntityExist(entity) then
                    local coords = GetEntityCoords(entity)
                    local distance = #(playerCoords - coords)
                    if distance <= markerDistance then
                        local modelData = chairModelsByHash[GetEntityModel(entity)]
                        local seat = getModelSeat(entity)
                        local occupied = seat and occupiedSeats[seat.key] ~= nil
                        DrawMarker(2, coords.x, coords.y, coords.z + 0.65, 0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0, 0.22, 0.22, 0.22,
                            occupied and 255 or 80, occupied and 70 or 220, 100, 210,
                            false, true, 2, false, nil, nil, false)
                        drawDebugText(coords, ('%s | %s'):format(
                            modelData and modelData.name or 'chair', occupied and '使用中' or '空席'))
                    end

                end
            end

            for _, fixedSeat in ipairs(Config.FixedSeats) do
                local distance = #(playerCoords - fixedSeat.coords)
                if distance <= markerDistance then
                    local seatKey = 'fixed:' .. fixedSeat.id
                    local occupied = occupiedSeats[seatKey] ~= nil
                    DrawMarker(2, fixedSeat.coords.x, fixedSeat.coords.y, fixedSeat.coords.z + 0.65,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 0.25,
                        occupied and 255 or 80, occupied and 70 or 220, 100, 210,
                        false, true, 2, false, nil, nil, false)
                    drawDebugText(fixedSeat.coords,
                        ('%s | %s'):format(fixedSeat.id, occupied and '使用中' or '空席'))
                end
            end
            Wait(0)
        elseif currentSeat then
            local ped = PlayerPedId()
            if IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, false) then
                standUp()
            else
                DisableControlAction(0, 21, true) -- sprint
                DisableControlAction(0, 22, true) -- jump
                DisableControlAction(0, 24, true) -- attack
                DisableControlAction(0, 25, true) -- aim
                DisableControlAction(0, 30, true) -- move left/right
                DisableControlAction(0, 31, true) -- move forward/back
                DisableControlAction(0, 44, true) -- cover
                DisableControlAction(0, 140, true) -- melee light
                DisableControlAction(0, 141, true) -- melee heavy
                DisableControlAction(0, 142, true) -- melee alternate
                DisableControlAction(0, 257, true) -- attack 2
                Wait(0)
            end
        else
            Wait(300)
        end
    end
end)

CreateThread(function()
    while true do
        if seatGhostEnabled then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            for _, entity in ipairs(ghostObjectCache) do
                if DoesEntityExist(entity)
                    and #(playerCoords - GetEntityCoords(entity)) <= Config.SeatDebug.ghostDistance then
                    SetEntityNoCollisionEntity(ped, entity, true)
                end
            end
            drawSetupHelp('オブジェクト貫通 ON  |  /omnite_seatghost で解除')
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if seatGhostEnabled then
            local objects = GetGamePool('CObject')
            local nearbyObjects = {}
            local playerCoords = GetEntityCoords(PlayerPedId())
            for _, entity in ipairs(objects) do
                if #(playerCoords - GetEntityCoords(entity)) <= Config.SeatDebug.ghostScanDistance then
                    nearbyObjects[#nearbyObjects + 1] = entity
                end
            end
            ghostObjectCache = nearbyObjects
            Wait(500)
        else
            ghostObjectCache = {}
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if seatDebugEnabled then
            local objects = GetGamePool('CObject')
            local nearbyChairs = {}
            local playerCoords = GetEntityCoords(PlayerPedId())
            for _, entity in ipairs(objects) do
                if chairModelsByHash[GetEntityModel(entity)]
                    and #(playerCoords - GetEntityCoords(entity)) <= Config.SeatDebug.markerDistance then
                    nearbyChairs[#nearbyChairs + 1] = entity
                end
            end
            debugObjectCache = nearbyChairs
            Wait(750)
        else
            debugObjectCache = {}
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    seatDebugEnabled = false
    seatGhostEnabled = false
    debugObjectCache = {}
    ghostObjectCache = {}
    if setupState then endSeatSetup(false) end
    if currentSeat or pendingSeatKey then standUp() end
    for _, zoneId in ipairs(fixedZoneIds) do
        exports.ox_target:removeZone(zoneId)
    end
    if #targetModels > 0 then
        exports.ox_target:removeModel(targetModels, 'ptech_omnite_seating:sit')
    end
end)
