local C = SeatingClient
local prefix = 'ptech_omnite_seating:'
local placements, zones, zoneRevisions, editor = {}, {}, {}, nil
local opening = false
local nextSession = 0
local management
local nearbyMarkers = {}

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
    local carried = tonumber(LocalPlayer.state.emsEscorting)
    for _, choice in ipairs(choices) do
        if tonumber(choice.value) == carried then
            call('placePatient', carried, id)
            return
        end
    end
    local input=lib.inputDialog('ベッドへ移す患者',{{type='select',label='患者',options=choices,required=true}})
    if input then call('placePatient',tonumber(input[1]),id) end
end
AddEventHandler(prefix .. 'client:choosePatient',choosePatient)

local function cleanup()
    if editor and editor.preview and DoesEntityExist(editor.preview) then DeleteEntity(editor.preview) end
    editor = nil
    C.placing = false
    lib.hideTextUI()
    SendNUIMessage({action='placementClose'})
    SetNuiFocus(false,false)
end

local function preview()
    local e=editor
    if not e or not DoesEntityExist(e.preview) then return end
    local style=e.styles[e.styleIndex]
    if style.dict and not HasAnimDictLoaded(style.dict) then
        if not pcall(lib.requestAnimDict,style.dict,5000) or editor~=e then return end
    end
    local c,ped=e.coords,e.preview
    local o=style.offset or vec3(0,0,0)
    local h=math.rad(e.heading)
    local x,y,z=c.x+math.cos(h)*o.x-math.sin(h)*o.y,c.y+math.sin(h)*o.x+math.cos(h)*o.y,c.z+o.z
    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped,c.x,c.y,c.z,false,false,false)
    SetEntityHeading(ped,e.heading)
    if style.dict then TaskPlayAnimAdvanced(ped,style.dict,style.clip,x,y,z,0,0,(e.heading+(style.headingOffset or 0))%360,8,-8,-1,1,0,false,false)
    else TaskStartScenarioAtPosition(ped,style.scenario,x,y,z,(e.heading+(style.headingOffset or 0))%360,-1,true,true) end
end

local function sendEditor()
    if not editor then return end
    local styles={}
    for _,style in ipairs(editor.styles) do styles[#styles+1]=style.label end
    SendNUIMessage({action='placementState',session=editor.session,name=editor.name,mlo=editor.mlo,
        kind=editor.kind,values=editor.values,styles=styles,saving=editor.saving==true,
        focused=editor.focused,error=editor.error,heightMin=editor.heightMin,heightMax=editor.heightMax})
end

local function drawEditorAxes(e)
    local c,h=e.coords,math.rad(e.heading)
    local right={x=math.cos(h),y=math.sin(h),z=0}
    local forward={x=-math.sin(h),y=math.cos(h),z=0}
    local function line(a,b,r,g,bcol)
        DrawLine(a.x,a.y,a.z,b.x,b.y,b.z,r,g,bcol,230)
    end
    local function axis(direction,side,r,g,b,label)
        local tip={x=c.x+direction.x*0.85,y=c.y+direction.y*0.85,z=c.z+direction.z*0.85}
        line(c,tip,r,g,b)
        for _,sign in ipairs({-1,1}) do
            line(tip,{x=tip.x-direction.x*0.14+side.x*0.07*sign,
                y=tip.y-direction.y*0.14+side.y*0.07*sign,
                z=tip.z-direction.z*0.14+side.z*0.07*sign},r,g,b)
        end
        C.drawText(vec3(tip.x,tip.y,tip.z+0.04),label)
    end
    axis(right,forward,240,70,70,'~r~X / 左右')
    axis(forward,right,70,230,100,'~g~Y / 前後')
    axis({x=0,y=0,z=1},right,70,150,255,'~b~Z / 高さ')
    -- 水平リングは、現在対応しているZ軸回転（向き）を示す。
    local radius=0.6
    for i=0,47 do
        local a,b=i*math.pi/24,(i+1)*math.pi/24
        line({x=c.x+math.cos(a)*radius,y=c.y+math.sin(a)*radius,z=c.z},
            {x=c.x+math.cos(b)*radius,y=c.y+math.sin(b)*radius,z=c.z},70,150,255)
    end
end

local function applyValues(data)
    if not editor or editor.saving or editor.grounding or type(data)~='table' or data.session~=editor.session then return false end
    local v=data.values
    if type(v)~='table' then return false end
    for _,key in ipairs({'right','forward','height','heading','style'}) do
        if type(v[key])~='number' or v[key]~=v[key] or math.abs(v[key])>10000 then return false end
    end
    local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
    local values={right=clamp(v.right,-2,2),forward=clamp(v.forward,-2,2),height=clamp(v.height,editor.heightMin,editor.heightMax),
        heading=v.heading%360,style=clamp(math.floor(v.style),1,#editor.styles)}
    local h=math.rad(values.heading)
    local c=editor.coords
    local right,forward=values.right-editor.values.right,values.forward-editor.values.forward
    editor.coords=vec3(c.x+math.cos(h)*right-math.sin(h)*forward,
        c.y+math.sin(h)*right+math.cos(h)*forward,editor.origin.z+values.height)
    editor.heading,editor.styleIndex,editor.values=values.heading,values.style,values
    editor.dirty=true
    editor.error=nil
    return true
end

local function saveEditor()
    local e=editor
    if not e or e.saving then return end
    e.saving=true e.error=nil sendEditor()
    CreateThread(function()
        local result=call('save',{id=e.id,revision=e.revision,mlo=e.mlo,name=e.name,kind=e.kind,group=e.group,
            coords={x=e.coords.x,y=e.coords.y,z=e.coords.z},heading=e.heading,style=e.styles[e.styleIndex].id})
        if editor~=e then return end
        e.saving=false
        if result then cleanup() C.notify('DBへ保存しました。すぐに利用できます。')
        else e.error='保存できませんでした。通知内容を確認して、もう一度お試しください。' sendEditor() end
    end)
end

RegisterNUICallback('placementUpdate',function(data,cb)
    cb({ok=applyValues(data)})
end)
RegisterNUICallback('placementSave',function(data,cb)
    local ok=applyValues(data)
    cb({ok=ok})
    if ok then saveEditor() end
end)
RegisterNUICallback('placementGround',function(data,cb)
    if not applyValues(data) then cb({ok=false}) return end
    local e=editor
    e.grounding=true
    preview()
    Wait(200)
    if editor~=e then cb({ok=false}) return end
    local p=GetEntityCoords(PlayerPedId())
    local minimum=GetModelDimensions(GetEntityModel(PlayerPedId()))
    local startZ=p.z+minimum.z+0.3
    local handle=StartShapeTestRay(e.coords.x,e.coords.y,startZ,e.coords.x,e.coords.y,startZ-20.0,17,PlayerPedId(),7)
    local deadline=GetGameTimer()+1500
    local status,hit,point
    repeat
        Wait(0)
        status,hit,point=GetShapeTestResult(handle)
    until status~=1 or GetGameTimer()>deadline or editor~=e
    if editor~=e then cb({ok=false}) return end
    e.grounding=false
    local found=status==2 and (hit==true or hit==1)
    if found then
        local left=GetPedBoneCoords(e.preview,0x3779,0.0,0.0,0.0)
        local right=GetPedBoneCoords(e.preview,0xCC4D,0.0,0.0,0.0)
        local height=e.coords.z+point.z-math.min(left.z,right.z)+0.02-e.origin.z
        e.heightMin=math.ceil(height*100)/100
        e.heightMax=math.max(2,e.heightMin+4)
        e.values.height=e.heightMin
        e.coords=vec3(e.coords.x,e.coords.y,e.origin.z+e.heightMin)
        e.dirty=true e.error=nil
    else e.error='足元の地面を取得できませんでした。同じ階の近くで試してください。' end
    sendEditor()
    cb({ok=found})
end)
RegisterNUICallback('placementCancel',function(data,cb)
    local ok=editor and not editor.saving and not editor.grounding and type(data)=='table' and data.session==editor.session
    if ok then cleanup() end
    cb({ok=ok==true})
end)

local function toggleEditorFocus()
    if not editor or editor.saving or editor.grounding then return end
    editor.focused=not editor.focused
    SetNuiFocus(editor.focused,editor.focused)
    sendEditor()
end
RegisterNUICallback('placementFocus',function(data,cb)
    if editor and type(data)=='table' and data.session==editor.session then toggleEditorFocus() end
    cb({ok=true})
end)
RegisterCommand('omnite_seatfocus',toggleEditorFocus,false)
RegisterCommand('omnite_seatfocus_alt',toggleEditorFocus,false)
RegisterKeyMapping('omnite_seatfocus_alt','座席配置のスライダーと視点操作を切り替え','keyboard','LMENU')

local function startEditor(data, existing)
    if not C.canStart() or C.placing then return end
    C.placing = true
    local coords, entity
    coords = vec3(data.coords.x,data.coords.y,data.coords.z)
    if not coords or not C.placing then cleanup() return end
    local styles=OmniteSeating.stylesFor(data.kind)
    if #styles==0 then cleanup() C.notify('この種類に対応する姿勢がありません。') return end
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
        id = data.id, revision = data.revision, mlo = data.mlo, name = data.name, group=data.group,
        kind = data.kind, coords = coords, heading = data.heading or GetEntityHeading(PlayerPedId()),
        styleIndex = 1, preview = ped, entity = entity,
        origin=coords,originHeading=data.heading or GetEntityHeading(PlayerPedId()),focused=true,styles=styles,heightMin=-2,heightMax=2,
    }
    for i, style in ipairs(styles) do if style.id == data.style then editor.styleIndex = i end end
    nextSession=nextSession+1
    editor.session=nextSession
    editor.values={right=0,forward=0,height=0,heading=editor.heading,style=editor.styleIndex}
    preview()
    lib.hideTextUI()
    sendEditor()
    SetNuiFocus(true,true)
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
                label = (data.kind == 'chair' or data.kind == 'counter') and '座る' or '横になる',
                icon = (data.kind == 'chair' or data.kind == 'counter') and 'fa-solid fa-chair' or 'fa-solid fa-bed',
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

local function stopManagement()
    management=nil
    nearbyMarkers={}
    C.managing=false
    cleanup()
end

local function newSeatName(previous)
    local random, serial = math.random(0,999999), GetGameTimer()
    while true do
        local name=('seat_%06d_%d'):format(random,serial)
        local used=name==previous
        for _,seat in pairs(placements) do if seat.name==name then used=true break end end
        if not used then return name end
        serial=serial+1
    end
end

local function showRegistration(draft)
    if not management then return end
    local m=management
    local auth=call('tool')
    if management~=m then return end
    if not auth then m.menu=false return end
    m.auth=auth
    local selected
    for _,entry in ipairs(auth.mlos or {}) do if entry.id==draft.mlo then selected=entry.label break end end
    local function showAgain() if management==m then showRegistration(draft) end end
    lib.registerContext({id='omnite_seat_create',title='登録情報',onExit=function() if management==m then m.menu=false end end,options={
        {title='MLOを登録',description=draft.group and '同じ家具のMLOを引き継ぎます' or '新しいMLO名を登録します',disabled=draft.group~=nil,onSelect=function()
            local input=lib.inputDialog('MLOを登録',{{type='input',label='MLO名',required=true,minLength=1,maxLength=64}})
            if input and management==m then
                local result=call('registerMlo',input[1])
                if result then draft.mlo=result.id C.notify('MLO名を登録しました。') end
            end
            showAgain()
        end},
        {title='MLOを選択',description=selected or '未選択',disabled=draft.group~=nil,onSelect=function()
            local choices={}
            for _,entry in ipairs(auth.mlos or {}) do choices[#choices+1]={value=entry.id,label=entry.label} end
            if #choices==0 then C.notify('先に「MLOを登録」で名前を登録してください。') showAgain() return end
            local input=lib.inputDialog('MLOを選択',{{type='select',label='登録済みMLO',options=choices,required=true,default=draft.mlo,searchable=true}})
            if input then draft.mlo=input[1] end
            showAgain()
        end},
        {title='座席名を指定',description=draft.name and draft.name~='' and draft.name or '未入力：自動でランダム名を付けます',onSelect=function()
            local input=lib.inputDialog('座席名を指定',{{type='input',label='座席名（省略可）',default=draft.name or '',maxLength=64}})
            if input then draft.name=input[1] end
            showAgain()
        end},
        {title='種類を指定',description=({chair='イス',counter='カウンター',bed='ベッド',patient_bed='病院ベッド'})[draft.kind],onSelect=function()
            local kinds={{value='chair',label='イス'},{value='counter',label='カウンター'},{value='bed',label='ベッド'}}
            if auth.ems then kinds[#kinds+1]={value='patient_bed',label='病院ベッド'} end
            local input=lib.inputDialog('種類を指定',{{type='select',label='種類',required=true,default=draft.kind,options=kinds}})
            if input then draft.kind=input[1] end
            showAgain()
        end},
        {title='作成',description='スライダーで位置と姿勢を調整します',disabled=not selected,onSelect=function()
            if management~=m then return end
            local latest=call('tool')
            if not latest then m.menu=false return end
            if draft.kind=='patient_bed' and not latest.ems then C.notify('病院ベッドは医療職のみ作成できます。') showAgain() return end
            local name=draft.name
            if not name or name=='' then name=newSeatName() end
            local length=utf8.len(name)
            if not length or length>64 or name:find('%c') or not name:match('%S') then C.notify('座席名は64文字以内で指定してください。') showAgain() return end
            m.menu=false
            startEditor({mlo=draft.mlo,name=name,kind=draft.kind,coords=draft.coords,heading=draft.heading,group=draft.group},true)
        end},
    }})
    lib.showContext('omnite_seat_create')
end

local editMarker
editMarker=function(data)
    local m=management
    if not m then return end
    m.menu=true
    local auth=call('tool')
    if management~=m then return end
    if not auth then m.menu=false return end
    if data.fixed then C.notify('この地点はConfigで登録されています。設定ファイルで編集してください。') m.menu=false return end
    local owns=auth.admin or data.owner==auth.owner
    if not (owns or Config.Placement.editByToolHolder or Config.Placement.deleteByToolHolder) or (data.kind=='patient_bed' and not auth.ems) then
        C.notify('この地点を変更する権限がありません。') m.menu=false return
    end
    lib.registerContext({id='omnite_seat_edit',title=data.name or data.id,
        onExit=function() if management==m then m.menu=false end end,options={
        {title='編集',disabled=not (owns or Config.Placement.editByToolHolder),onSelect=function()
            if management~=m then return end
            m.menu=false startEditor(data,true)
        end},
        {title='削除',disabled=not (owns or Config.Placement.deleteByToolHolder),onSelect=function()
            local confirmed=lib.alertDialog({header='登録地点を削除',content=(data.name or data.id)..' を削除しますか？',cancel=true})
            if management~=m then return end
            if confirmed=='confirm' and call('delete',{id=data.id,revision=data.revision}) then C.notify('削除しました。') end
            m.menu=false
        end},
        {title='同じ家具に利用地点を追加',disabled=not owns,description='ベンチの別の席や、ソファの寝る地点を追加します',onSelect=function()
            if management~=m then return end
            showRegistration({mlo=data.mlo,kind=data.kind,group=data.group,coords=data.coords,heading=data.heading})
        end},
        {title='同じ家具の利用地点',description='このグループの席・寝る地点を一覧で管理します',onSelect=function()
            if management~=m then return end
            local options={}
            for _,point in pairs(placements) do
                if data.group and point.group==data.group then
                    local entry=point
                    options[#options+1]={title=entry.name,description=({chair='イス',counter='カウンター',bed='ベッド',patient_bed='病院ベッド'})[entry.kind],onSelect=function() editMarker(entry) end}
                end
            end
            table.sort(options,function(a,b) return a.title<b.title end)
            lib.registerContext({id='omnite_furniture_points',title='同じ家具の利用地点',options=options,onExit=function() if management==m then m.menu=false end end})
            lib.showContext('omnite_furniture_points')
        end},
        {title='コピーして新規作成',description='設定を引き継ぎ、新しいIDで保存します。自動生成の名前も新しく振り直します',onSelect=function()
            if management~=m then return end
            local source=placements[data.id]
            if not source then C.notify('コピー元の地点は削除されています。') m.menu=false return end
            local latest=call('tool')
            if management~=m then return end
            if not latest then m.menu=false return end
            if source.kind=='patient_bed' and not latest.ems then C.notify('病院ベッドは医療職のみ作成できます。') m.menu=false return end
            -- ID・更新番号・所有者・家具グループは引き継がず、独立した地点として作成する。
            local name=source.name
            if not name or name=='' or name:match('^seat_%d%d%d%d%d%d_%d+$') then name=newSeatName(name) end
            m.menu=false
            startEditor({mlo=source.mlo,name=name,kind=source.kind,
                coords=source.coords,heading=source.heading,style=source.style},false)
        end},
    }})
    lib.showContext('omnite_seat_edit')
end

local function beginManagement()
    if management or C.busy() or C.placing then return end
    local auth=call('tool')
    if not auth then return end
    management={auth=auth,menu=false}
    C.managing=true
    C.notify('管理モード：マーカーの近くでEを押すと編集できます。')
end

local function managementAction(existing)
    if not management or management.menu or editor then return end
    if existing then editMarker(existing) return end
    local ped=PlayerPedId()
    local coords=GetEntityCoords(ped)
    management.menu=true
    showRegistration({coords={x=coords.x,y=coords.y,z=coords.z},heading=GetEntityHeading(ped),kind='chair'})
end

local function openTool()
    if opening or C.busy() or C.placing or management then return end
    opening=true
    local auth=call('tool')
    opening=false
    if not auth then return end
    local options={{title='椅子やベッドの管理',description='管理モードに入り、近くの登録地点を表示します',onSelect=beginManagement}}
    options[#options+1]={title='テレポーターの管理',description='2点を指定し、一方通行・双方向の移動を登録します',onSelect=function()
        if C.openTeleporters then C.openTeleporters() end
    end}
    if auth.admin and GetResourceState('ptech_omnite_delivery')=='started' then
        options[#options+1]={title='配達・素材仕入れの管理',icon='truck-fast',onSelect=function()
            exports.ptech_omnite_delivery:openManager()
        end}
    end
    if auth.admin then options[#options+1]={title='サークルエリアの管理',onSelect=function()
        if C.openCircles then C.openCircles() end
    end} end
    if auth.admin then options[#options+1]={title='DBからConfigへ出力',onSelect=function()
        local choices={{value='__all',label='すべて'}}
        for _,entry in ipairs(auth.mlos or {}) do choices[#choices+1]={value=entry.id,label=entry.label} end
        local input=lib.inputDialog('Config出力',{{type='select',label='MLO',options=choices,default='__all',required=true}})
        if not input then return end
        local result=call('export',input[1]~='__all' and input[1] or nil)
        if result then C.copy(result.text) end
    end} end
    lib.registerContext({id='omnite_seat_tool',title='Omini工具箱',options=options})
    lib.showContext('omnite_seat_tool')
end


-- 工具箱の「使う」から開始。インベントリ側の利用成功後に所持・権限を再確認する。
exports('usePlacementTool', function(data)
    if opening or C.busy() or C.placing or management then return end
    exports.ox_inventory:useItem(data, function(used)
        if used then openTool() end
    end)
end)

RegisterNetEvent(prefix .. 'client:openPlacement', openTool)
RegisterCommand(Config.Placement.command,openTool,false)

local function accessMarkers(candidates)
    if #candidates==0 then managementAction() return end
    if #candidates==1 then managementAction(candidates[1].data) return end
    local m=management
    if not m then return end
    m.menu=true
    table.sort(candidates,function(a,b)
        if math.abs(a.distance-b.distance)>0.001 then return a.distance<b.distance end
        return tostring(a.data.id)<tostring(b.data.id)
    end)
    local options={}
    local labels={chair='イス',counter='カウンター',bed='ベッド',patient_bed='病院ベッド'}
    for _,candidate in ipairs(candidates) do
        local entry=candidate
        options[#options+1]={title=entry.data.name or entry.data.id,
            description=('%s / %s / %.2fm / ID %s'):format(entry.label or entry.data.mlo or '',labels[entry.data.kind] or '席',entry.distance,entry.data.id),
            onSelect=function()
                if management~=m then return end
                m.menu=false
                local data=entry.data.fixed and entry.data or placements[entry.data.id]
                if not data then C.notify('この地点は削除されています。') return end
                local c=data.coords and vec3(data.coords.x,data.coords.y,data.coords.z) or entry.coords
                if #(GetEntityCoords(PlayerPedId())-c)>Config.Placement.markerInteractDistance then C.notify('選択した地点に近づいてください。') return end
                managementAction(data)
            end}
    end
    lib.registerContext({id='omnite_seat_access',title='操作するポイントを選択',options=options,onExit=function() if management==m then m.menu=false end end})
    lib.showContext('omnite_seat_access')
end

local function managementFrame()
    local m=management
    local ped=PlayerPedId()
    if not m then return end
    if IsPedDeadOrDying(ped,true) or IsPedInAnyVehicle(ped,false) then stopManagement() return end
    local playerCoords=GetEntityCoords(ped)
    local candidates={}
    for _,marker in ipairs(nearbyMarkers) do
        local distance=#(playerCoords-marker.coords)
        if distance<=Config.Placement.markerDistance then
            local data=marker.data
            local editable=not data.fixed and (Config.Placement.editByToolHolder or Config.Placement.deleteByToolHolder or m.auth.admin or data.owner==m.auth.owner) and (data.kind~='patient_bed' or m.auth.ems)
            DrawMarker(2,marker.coords.x,marker.coords.y,marker.coords.z+0.35,0,0,0,0,0,0,0.18,0.18,0.18,
                editable and 100 or 180,editable and 220 or 180,180,190,false,true,2,false,nil,nil,false)
            C.drawText(marker.coords,(marker.label or data.mlo or '')..' / '..(data.name or data.id))
            if distance<=Config.Placement.markerInteractDistance then candidates[#candidates+1]={data=data,coords=marker.coords,label=marker.label,distance=distance} end
        end
    end
    if m.menu then lib.hideTextUI() return end
    lib.showTextUI(#candidates>0 and '椅子・ベッド管理 | E：ポイントを選択・編集 / Shift+E：現在地に新規登録 / Esc：管理終了'
        or '椅子・ベッド管理 | E：現在地に新規登録 / Esc：管理終了')
    DisableControlAction(0,38,true)
    DisableControlAction(0,202,true)
    if IsDisabledControlJustPressed(0,202) then stopManagement()
    elseif IsDisabledControlJustPressed(0,38) then
        if IsControlPressed(0,21) then managementAction() else accessMarkers(candidates) end
    end
end

CreateThread(function()
    while true do
        if management then
            local markers={}
            local labels={}
            for _,entry in ipairs(management.auth.mlos or {}) do labels[entry.id]=entry.label end
            local p=GetEntityCoords(PlayerPedId())
            for _,seat in pairs(placements) do
                local coords=vec3(seat.coords.x,seat.coords.y,seat.coords.z)
                if #(p-coords)<=Config.Placement.markerDistance then markers[#markers+1]={data=seat,coords=coords,label=labels[seat.mlo]} end
            end
            for _,seat in ipairs(Config.FixedSeats) do
                if (seat.bucket or 0)==C.bucket and #(p-seat.coords)<=Config.Placement.markerDistance then
                    markers[#markers+1]={coords=seat.coords,label=labels[seat.mlo],data={fixed=true,id=seat.id,name=seat.name or seat.id,mlo=seat.mlo,kind=seat.kind or 'chair'}}
                end
            end
            nearbyMarkers=markers
        else nearbyMarkers={} end
        Wait(500)
    end
end)

CreateThread(function()
    local controls = {30,31,21,22,24,25,140,141,142}
    while true do
        if editor then
            local e = editor
            for _, control in ipairs(controls) do
                if e.focused or (control~=30 and control~=31 and control~=21) then DisableControlAction(0,control,true) end
            end
            if editor == e then
                if IsPedDeadOrDying(PlayerPedId(),true) or IsPedInAnyVehicle(PlayerPedId(),false) then cleanup()
                else
                    if e.dirty and (not e.lastPreview or GetGameTimer()-e.lastPreview>=50) then
                        e.dirty=false e.lastPreview=GetGameTimer() preview()
                    end
                    if e.entity and DoesEntityExist(e.entity) then SetEntityNoCollisionEntity(PlayerPedId(),e.entity,true) end
                    DrawMarker(28,e.coords.x,e.coords.y,e.coords.z,0,0,0,0,0,0,0.08,0.08,0.08,80,200,255,180,false,false,2,false,nil,nil,false)
                    drawEditorAxes(e)
                end
            end
            Wait(0)
        elseif management then
            managementFrame()
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

AddEventHandler('QBCore:Client:OnPlayerUnload',stopManagement)
AddEventHandler('onResourceStop',function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopManagement()
    for _, zone in pairs(zones) do exports.ox_target:removeZone(zone) end
end)
