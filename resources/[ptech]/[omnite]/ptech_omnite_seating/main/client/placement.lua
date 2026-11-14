local C = SeatingClient
local prefix = 'ptech_omnite_seating:'
local placements, zones, zoneRevisions, editor = {}, {}, {}, nil
local opening = false

local function call(action, ...)
    local ok, result = pcall(lib.callback.await, prefix .. action, false, ...)
    if not ok or not result then C.notify('サーバーから応答がありません。') return end
    if not result.ok then C.notify(result.message or '操作できませんでした。') return end
    return result
end

local function choosePatient(id)
    local choices={}
    local coords=GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() and #(coords-GetEntityCoords(GetPlayerPed(player))) <= Config.Seating.serverDistance then
            local sid=GetPlayerServerId(player)
            choices[#choices+1]={value=tostring(sid),label=('ID %d'):format(sid)}
        end
    end
    if #choices==0 then C.notify('近くに患者がいません。') return end
    local input=lib.inputDialog('ベッドへ移す患者',{{type='select',label='患者',options=choices,required=true}})
    if input then call('placePatient',tonumber(input[1]),id) end
end
AddEventHandler(prefix .. 'client:choosePatient',choosePatient)

local function cleanup()
    if editor and editor.preview and DoesEntityExist(editor.preview) then DeleteEntity(editor.preview) end
    editor = nil
    C.placing = false
    lib.hideTextUI()
end

local function preview()
    local e = editor
    if not e or not DoesEntityExist(e.preview) then return end
    local c, ped = e.coords, e.preview
    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, e.heading)
    if e.kind == 'chair' then
        local style = Config.Seating.styles[e.styleIndex]
        local offset = style.offset or vec3(0,0,0)
        local h = math.rad(e.heading)
        TaskStartScenarioAtPosition(ped, style.scenario,
            c.x + math.cos(h)*offset.x - math.sin(h)*offset.y,
            c.y + math.sin(h)*offset.x + math.cos(h)*offset.y,
            c.z + offset.z, (e.heading + (style.headingOffset or 0)) % 360, -1, true, true)
    else
        local a = Config.Placement.bedAnimation
        TaskPlayAnimAdvanced(ped, a.dict, a.clip, c.x,c.y,c.z,0,0,e.heading,8,-8,-1,1,0,false,false)
    end
end

local function raycast()
    local c, r = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local pitch, yaw = math.rad(r.x), math.rad(r.z)
    local d = vec3(-math.sin(yaw)*math.cos(pitch), math.cos(yaw)*math.cos(pitch), math.sin(pitch))
    local dest = c + d * Config.Placement.maxDistance
    local handle = StartShapeTestRay(c.x,c.y,c.z,dest.x,dest.y,dest.z,17,PlayerPedId(),7)
    local status, hit, coords, normal, entity
    repeat
        Wait(0)
        status, hit, coords, normal, entity = GetShapeTestResult(handle)
    until status ~= 1
    if status == 2 and (hit == true or hit == 1) then return coords, entity end
end

local function selectPoint()
    lib.showTextUI('椅子・ベッドの利用位置に視点を合わせる | E 選択 / Esc キャンセル')
    while C.placing do
        DisableControlAction(0,38,true)
        DisableControlAction(0,202,true)
        if IsDisabledControlJustPressed(0,202) then return end
        if IsDisabledControlJustPressed(0,38) then
            local coords, entity = raycast()
            if coords and #(GetEntityCoords(PlayerPedId()) - coords) <= Config.Placement.maxDistance then
                return coords, entity
            end
            C.notify('近くの椅子・床面などに視点を合わせてください。')
        end
        if IsPedDeadOrDying(PlayerPedId(),true) then return end
        Wait(0)
    end
end

local function startEditor(data, existing)
    if not C.canStart() or C.placing then return end
    C.placing = true
    local coords, entity
    if existing then coords = vec3(data.coords.x,data.coords.y,data.coords.z) else coords, entity = selectPoint() end
    if not coords or not C.placing then cleanup() return end
    if data.kind ~= 'chair' then
        if not pcall(lib.requestAnimDict, Config.Placement.bedAnimation.dict, 5000) then
            cleanup() C.notify('姿勢の読み込みに失敗しました。') return
        end
    end
    if not C.placing then return end
    local ped = ClonePed(PlayerPedId(), false, false, false)
    if not ped or ped == 0 then cleanup() return end
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped,true)
    SetEntityCollision(ped,false,false)
    SetEntityHasGravity(ped,false)
    SetPedCanRagdoll(ped,false)
    FreezeEntityPosition(ped,true)
    SetBlockingOfNonTemporaryEvents(ped,true)
    SetEntityAlpha(ped,170,false)
    editor = {
        id = data.id, revision = data.revision, mlo = data.mlo, name = data.name,
        kind = data.kind, coords = coords, heading = data.heading or GetEntityHeading(PlayerPedId()),
        styleIndex = 1, preview = ped, entity = entity,
    }
    for i, style in ipairs(Config.Seating.styles) do if style.id == data.style then editor.styleIndex = i end end
    preview()
    lib.showTextUI('↑↓ 前後 / ←→ 左右 / E・Q 高さ / Z・C 回転 / G 姿勢\nShift 粗調整 / Enter DB保存 / Esc キャンセル')
end

RegisterNetEvent(prefix .. 'client:placements', function(state, bucket)
    C.bucket = bucket or C.bucket
    placements = state or {}
    for id, zone in pairs(zones) do
        if not placements[id] or placements[id].revision ~= zoneRevisions[id] then
            exports.ox_target:removeZone(zone)
            zones[id], zoneRevisions[id] = nil, nil
        end
    end
    for id, data in pairs(placements) do
        if not zones[id] then
        local seat = { key = 'db:' .. id, kind = data.kind,
            lockCoords = vec3(data.coords.x,data.coords.y,data.coords.z),
            sitCoords = vec3(data.coords.x,data.coords.y,data.coords.z), heading = data.heading,
            styleId = data.style,
        }
        local options = {{
                name = prefix .. 'placed:' .. id,
                label = data.kind == 'chair' and '座る' or '横になる',
                icon = data.kind == 'chair' and 'fa-solid fa-chair' or 'fa-solid fa-bed',
                distance = Config.Seating.targetDistance,
                canInteract = function()
                    return C.isAvailable(seat.key) and
                        (seat.kind ~= 'patient_bed' or GetResourceState(Config.Placement.medicalResource) == 'started')
                end,
                onSelect = function() C.requestSit(seat) end,
            }}
        if data.kind == 'patient_bed' then
            options[#options+1] = {
                name=prefix .. 'patient:' .. id, label='患者をベッドへ移す', icon='fa-solid fa-user-nurse',
                distance=Config.Seating.targetDistance,
                canInteract=function()
                    local player=exports.qbx_core:GetPlayerData()
                    return player and player.job and Config.Placement.emsJobs[player.job.name] == true
                        and GetResourceState(Config.Placement.medicalResource)=='started'
                end,
                onSelect=function()
                    choosePatient(id)
                end,
            }
        end
        zones[id] = exports.ox_target:addSphereZone({coords=seat.sitCoords,radius=0.45,options=options})
        zoneRevisions[id] = data.revision
        end
    end
end)

local function openList(auth)
    local options = {}
    local p = GetEntityCoords(PlayerPedId())
    for _, seat in pairs(placements) do
        local data = seat
        if (auth.admin or data.owner == auth.owner) and #(p-vec3(data.coords.x,data.coords.y,data.coords.z)) <= Config.Placement.maxDistance then
            options[#options+1] = {
                title = data.mlo .. ' / ' .. data.name,
                description = data.kind .. ' | ID ' .. data.id,
                onSelect = function()
                    lib.registerContext({ id = 'omnite_seat_edit', title = data.name, options = {
                        { title = '位置・姿勢を調整', onSelect = function() startEditor(data,true) end },
                        { title = '削除', onSelect = function()
                            if lib.alertDialog({ header = '座席を削除', content = data.mlo .. ' / ' .. data.name .. ' を削除しますか？', cancel = true }) ~= 'confirm' then return end
                            if call('delete', { id = data.id, revision = data.revision }) then C.notify('削除しました。') end
                        end },
                    }})
                    lib.showContext('omnite_seat_edit')
                end,
            }
        end
    end
    table.sort(options,function(a,b) return a.title < b.title end)
    if #options == 0 then C.notify('近くに編集できる座席がありません。') return end
    lib.registerContext({ id = 'omnite_seat_list', title = '近くの登録済み座席', options = options })
    lib.showContext('omnite_seat_list')
end

local function openTool()
    if opening or C.busy() or C.placing then return end
    opening = true
    local auth = call('tool')
    opening = false
    if not auth then return end
    local kinds = { {value='chair',label='椅子'}, {value='bed',label='通常ベッド'} }
    if auth.ems then kinds[#kinds+1] = {value='patient_bed',label='患者用ベッド（Mediora）'} end
    local options = {
        { title = '利用位置を新しく登録', onSelect = function()
            local input = lib.inputDialog('座席・ベッドの登録', {
                {type='input',label='MLO管理名（半角英数字・_・-）',required=true,min=1,max=64},
                {type='input',label='席の名前（空欄で自動生成）',max=64},
                {type='select',label='種類',required=true,default='chair',options=kinds},
            })
            if input then startEditor({mlo=input[1],name=input[2] and input[2] ~= '' and input[2] or ('seat_' .. GetGameTimer()),kind=input[3]}) end
        end },
        { title = '近くの登録済み座席を編集・削除', onSelect = function() openList(auth) end },
    }
    if auth.admin then options[#options+1] = { title = 'DBからConfigへ出力', onSelect = function()
        local input = lib.inputDialog('Config出力', {{type='input',label='MLO管理名（空欄ですべて）',max=64}})
        if not input then return end
        local result = call('export', input[1] and input[1] ~= '' and input[1] or nil)
        if result then C.copy(result.text) end
    end } end
    lib.registerContext({ id='omnite_seat_tool',title='Omnite 座席・ベッド設定',options=options })
    lib.showContext('omnite_seat_tool')
end

RegisterNetEvent(prefix .. 'client:openPlacement', openTool)
RegisterCommand(Config.Placement.command,openTool,false)

CreateThread(function()
    local controls = {172,173,174,175,38,44,20,26,47,191,202,21,24,25}
    while true do
        if editor then
            local e = editor
            for _, control in ipairs(controls) do DisableControlAction(0,control,true) end
            local c, h = e.coords, math.rad(e.heading)
            local step = IsDisabledControlPressed(0,21) and Config.SeatRecorder.coarseStep or Config.SeatRecorder.fineStep
            local changed = false
            if not e.saving then
                if IsDisabledControlJustPressed(0,172) then e.coords = c + vec3(-math.sin(h)*step,math.cos(h)*step,0) changed=true
                elseif IsDisabledControlJustPressed(0,173) then e.coords = c - vec3(-math.sin(h)*step,math.cos(h)*step,0) changed=true
                elseif IsDisabledControlJustPressed(0,174) then e.coords = c - vec3(math.cos(h)*step,math.sin(h)*step,0) changed=true
                elseif IsDisabledControlJustPressed(0,175) then e.coords = c + vec3(math.cos(h)*step,math.sin(h)*step,0) changed=true
                elseif IsDisabledControlJustPressed(0,38) then e.coords = c + vec3(0,0,step) changed=true
                elseif IsDisabledControlJustPressed(0,44) then e.coords = c - vec3(0,0,step) changed=true
                elseif IsDisabledControlJustPressed(0,20) then e.heading=(e.heading-Config.SeatRecorder.headingStep)%360 changed=true
                elseif IsDisabledControlJustPressed(0,26) then e.heading=(e.heading+Config.SeatRecorder.headingStep)%360 changed=true
                elseif IsDisabledControlJustPressed(0,47) and e.kind=='chair' then e.styleIndex=e.styleIndex % #Config.Seating.styles + 1 changed=true
                elseif IsDisabledControlJustPressed(0,191) then
                    e.saving=true
                    CreateThread(function()
                        local result = call('save', {id=e.id,revision=e.revision,mlo=e.mlo,name=e.name,kind=e.kind,
                            coords={x=e.coords.x,y=e.coords.y,z=e.coords.z},heading=e.heading,style=Config.Seating.styles[e.styleIndex].id})
                        if editor ~= e then return end
                        e.saving=false
                        if result then cleanup() C.notify('DBへ保存しました。すぐに利用できます。') end
                    end)
                elseif IsDisabledControlJustPressed(0,202) then cleanup() end
            end
            if editor == e then
                if IsPedDeadOrDying(PlayerPedId(),true) or IsPedInAnyVehicle(PlayerPedId(),false)
                    or #(GetEntityCoords(PlayerPedId())-e.coords) > Config.Placement.maxDistance then cleanup()
                else
                    if changed then preview() end
                    if e.entity and DoesEntityExist(e.entity) then SetEntityNoCollisionEntity(PlayerPedId(),e.entity,true) end
                    DrawMarker(28,e.coords.x,e.coords.y,e.coords.z,0,0,0,0,0,0,0.08,0.08,0.08,80,200,255,180,false,false,2,false,nil,nil,false)
                end
            end
            Wait(0)
        elseif C.debug() then
            local p = GetEntityCoords(PlayerPedId())
            for _, seat in pairs(placements) do
                local c = vec3(seat.coords.x,seat.coords.y,seat.coords.z)
                if #(p-c) <= Config.SeatDebug.markerDistance then C.drawText(c,seat.mlo .. ' / ' .. seat.name) end
            end
            Wait(0)
        else Wait(250) end
    end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload',cleanup)
AddEventHandler('onResourceStop',function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanup()
    for _, zone in pairs(zones) do exports.ox_target:removeZone(zone) end
end)
