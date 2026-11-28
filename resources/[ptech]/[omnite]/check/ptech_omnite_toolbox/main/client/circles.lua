local C=SeatingClient
local prefix='ptech_omnite_toolbox:circle:'
local points,blips,warnings={},{},{}
local manager,accessing,loggedOut=nil,false,false
local previewBlip, hintText
local appearanceEditing=false
local managementAdmin=false
local function kindLabel(p) return p.kind=='npc_repellent' and '人除けサークル' or 'スターターサークル' end
-- 自然発生NPCだけを、発生地点のXY円形判定で生成前に止めます。
AddEventHandler('populationPedCreating',function(x,y)
    if loggedOut then return end
    for _,p in pairs(points) do
        if p.kind=='npc_repellent' and p.enabled and (x-p.center.x)^2+(y-p.center.y)^2<=p.radius^2 then
            CancelEvent()
            return
        end
    end
end)
local function hint(text)
    if text==hintText then return end
    if text then lib.showTextUI(text,{position='bottom-center'})
    elseif hintText then lib.hideTextUI() end
    hintText=text
end
local function clearPreview()
    if previewBlip then RemoveBlip(previewBlip) previewBlip=nil end
end
local function radiusBlip(p,colour,alpha)
    local b=AddBlipForRadius(p.center.x+0.0,p.center.y+0.0,p.center.z+0.0,p.radius+0.0)
    SetBlipColour(b,colour)
    SetBlipAlpha(b,alpha)
    SetBlipAsShortRange(b,false)
    SetBlipDisplay(b,4)
    return b
end
local travellingPed
local bucket=0
local access
local targetZones={}
local function removeTargets()
    for _,zone in pairs(targetZones) do exports.ox_target:removeZone(zone) end
    targetZones={}
end
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok or not result then C.notify('サーバーから応答がありません。') return end
    if not result.ok then C.notify(result.message or '操作できませんでした。') return end
    return result
end
local function finish()
    clearPreview()
    hint(nil)
    manager=nil
    accessing=false
    C.circleManaging=false
end
local function removeBlips()
    for _,blip in pairs(blips) do RemoveBlip(blip) end
    blips={}
end
local function update(state,newBucket)
    removeBlips()
    removeTargets()
    local old=points
    points,bucket=state or {},newBucket or 0
    for id in pairs(warnings) do
        if not points[id] or not points[id].enabled or not old[id] or old[id].revision~=points[id].revision then warnings[id]=nil end
    end
    if manager and manager.bucket~=bucket then lib.hideContext(false) lib.closeInputDialog() finish() end
    for id,p in pairs(points) do
        if not loggedOut and p.kind~='npc_repellent' then
            local pointId=id
            targetZones[id]=exports.ox_target:addBoxZone({
                -- Captured coordinates are the player's origin, about a metre above the floor.
                -- Include the visible ground marker so a raycast onto the floor hits the zone.
                coords=vec3(p.center.x,p.center.y,p.center.z-0.5),
                size=vec3(2.0,2.0,3.0),rotation=0.0,drawSprite=true,
                options={{name=prefix..'access:'..id,label=p.name..'：アクセス',icon='fa-solid fa-circle-dot',
                    distance=Config.Circles.interactDistance,
                    canInteract=function()
                        local point=points[pointId]
                        return not loggedOut and not appearanceEditing and point~=nil and not manager and not accessing
                            and (point.kind~='npc_repellent' or managementAdmin)
                            and not C.busy() and not C.placing and not C.managing and C.canStart()
                    end,
                    onSelect=function()
                        local point=points[pointId]
                        if not point or loggedOut or #(GetEntityCoords(PlayerPedId())-vec3(point.center.x,point.center.y,point.center.z))>Config.Circles.interactDistance then return end
                        access(pointId)
                    end,
                }},
            })
        end
        if p.kind~='npc_repellent' and p.enabled and not loggedOut then
            blips[id]=radiusBlip(p,Config.Circles.blipColour,Config.Circles.blipAlpha)
        end
    end
end
local function escape(id)
    local input=lib.inputDialog('脱出パスワード',{{type='input',label='脱出パスワード',password=true,required=true,maxLength=32}})
    if input then call('escape',id,input[1]) end
end
local showDraft,showList
local function clone(p) return json.decode(json.encode(p)) end
local function coordinateText(p)
    return ('%.2f, %.2f, %.2f / %.1f°'):format(p.x,p.y,p.z,p.heading)
end
showDraft=function()
    local m=manager
    if not m then return end
    m.capture=nil
    local p=m.draft
    clearPreview()
    previewBlip=radiusBlip(p,5,Config.Circles.blipAlpha)
    local function again() if manager==m then showDraft() end end
    local options={}
    if p.id and p.kind~='npc_repellent' then options[#options+1]={title='脱出パスワード',onSelect=function()
        escape(p.id)
        if manager==m then finish() end
    end} end
    if p.kind=='npc_repellent' then
        options[#options+1]={title='サークルの設定',description=('%s / 半径 %.1fm'):format(p.name,p.radius),onSelect=function()
            local input=lib.inputDialog('人除けサークルの設定',{
                {type='input',label='名前',default=p.name,required=true,minLength=1,maxLength=64},
                {type='number',label='半径（m）',default=p.radius,required=true,min=2,max=Config.Circles.maxRadius},
                {type='checkbox',label='有効化',checked=p.enabled},
            })
            if manager~=m then return end
            if input then p.name,p.radius,p.enabled=input[1],input[2],input[3]==true end
            again()
        end}
    else
    options[#options+1]={title='サークルの設定',description=('%s / 半径 %.1fm / %d秒'):format(p.name,p.radius,p.delay),onSelect=function()
        local input=lib.inputDialog('サークルの設定',{
            {type='input',label='名前',default=p.name,required=true,minLength=1,maxLength=64},
            {type='number',label='半径（m）',default=p.radius,required=true,min=2,max=Config.Circles.maxRadius},
            {type='input',label='範囲外で表示するメッセージ（{seconds} は残り秒数）',default=p.message,maxLength=256},
            {type='number',label='連れ戻すまでの秒数',default=p.delay,required=true,min=0,max=Config.Circles.maxDelay,precision=0},
            {type='checkbox',label='有効化',checked=p.enabled},
        })
        if manager~=m then return end
        if input then p.name,p.radius,p.message,p.delay,p.enabled=input[1],input[2],input[3] or '',input[4],input[5]==true end
        again()
    end}
    end
    local locations={{key='center',label='編集ポイント・サークル中心'}}
    if p.kind~='npc_repellent' then locations[#locations+1]={key='destination',label='連れ戻し先'} end
    for _,item in ipairs(locations) do
        local key,label=item.key,item.label
        options[#options+1]={title=label..'を指定',description=coordinateText(p[key]),onSelect=function()
            if manager~=m then return end
            m.capture=key
            C.notify('指定する場所に移動してE。Escで戻ります。')
        end}
    end
    options[#options+1]={title=p.enabled and '無効化して保存' or '有効化して保存',onSelect=function()
        local input=clone(p)
        input.enabled=not p.enabled
        if call('save',input) then finish() C.notify('サークルを更新しました。') else again() end
    end}
    options[#options+1]={title='保存',onSelect=function()
        if call('save',p) then finish() C.notify('サークルを保存しました。') else again() end
    end}
    if p.id then options[#options+1]={title='削除',onSelect=function()
        local answer=lib.alertDialog({header='サークルの削除',content=p.name..'を削除しますか？',cancel=true})
        if manager~=m then return end
        if answer=='confirm' and call('delete',p.id,p.revision) then finish() else again() end
    end} end
    lib.registerContext({id='omnite_circle_edit',title=kindLabel(p)..'の編集',options=options,onExit=finish})
    lib.showContext('omnite_circle_edit')
end
showList=function()
    local m=manager
    local result=call('list')
    if manager~=m then return end
    if not result or not result.admin then finish() return end
    managementAdmin=result.admin==true
    m.bucket=result.bucket
    update(result.points,result.bucket)
    local options={}
    for _,kind in ipairs({'starter','npc_repellent'}) do
    local circleKind=kind
    options[#options+1]={title=kindLabel({kind=circleKind})..'を設置',onSelect=function()
        local result=call('capture')
        if manager~=m then return end
        if not result then showList() return end
        m.draft={kind=circleKind,name=kindLabel({kind=circleKind}),center=result.point,destination=clone(result.point),radius=50.0,delay=10,
            message='範囲外です。{seconds}秒後に連れ戻されます。',enabled=false}
        if circleKind=='npc_repellent' then m.draft.destination,m.draft.delay,m.draft.message=nil,nil,nil end
        showDraft()
    end}
    end
    local entries={}
    for _,p in pairs(points) do entries[#entries+1]=p end
    table.sort(entries,function(a,b) return tonumber(a.id)<tonumber(b.id) end)
    for _,p in ipairs(entries) do
        local entry=p
        options[#options+1]={title=entry.name,description=kindLabel(entry)..' / '..(entry.enabled and '有効' or '無効'),onSelect=function()
            if manager~=m then return end
            m.draft=clone(entry)
            showDraft()
        end}
    end
    lib.registerContext({id='omnite_circle_list',title='サークルエリアの管理',options=options,onExit=finish})
    lib.showContext('omnite_circle_list')
end
function C.openCircles()
    if manager or accessing or C.busy() or C.placing or C.managing or not C.canStart() then return end
    manager={bucket=bucket}
    C.circleManaging=true
    showList()
end
access=function(id)
    if loggedOut or accessing or manager or C.busy() or C.placing or C.managing or not C.canStart() then return end
    accessing=true
    C.circleManaging=true
    local result=call('list')
    if not accessing then return end
    local p=result and result.points[id]
    if not p then finish() return end
    if result.admin then
        manager={bucket=result.bucket,draft=clone(p)}
        accessing=false
        showDraft()
    else
        escape(id)
        finish()
    end
end
RegisterNetEvent(prefix..'state',update)
RegisterNetEvent(prefix..'warning',function(id,active,message,seconds)
    if active then warnings[id]={message=message,deadline=GetGameTimer()+seconds*1000} else warnings[id]=nil end
end)
RegisterNetEvent(prefix..'clearWarnings',function() warnings={} end)
RegisterNetEvent(prefix..'travel',function(d)
    if loggedOut then return end
    lib.hideContext(false)
    lib.closeInputDialog()
    finish()
    C.teleporting=true
    local ped=PlayerPedId()
    travellingPed=ped
    FreezeEntityPosition(ped,true)
    local ok,err=xpcall(function()
        DoScreenFadeOut(150)
        local deadline=GetGameTimer()+750
        while not IsScreenFadedOut() and GetGameTimer()<deadline do Wait(0) end
        ClearPedTasksImmediately(ped)
        RequestCollisionAtCoord(d.x,d.y,d.z)
        SetEntityCoordsNoOffset(ped,d.x,d.y,d.z,false,false,false)
        SetEntityHeading(ped,d.heading)
        deadline=GetGameTimer()+5000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer()<deadline do
            RequestCollisionAtCoord(d.x,d.y,d.z) Wait(0)
        end
    end,debug.traceback)
    FreezeEntityPosition(ped,false)
    travellingPed=nil
    DoScreenFadeIn(150)
    C.teleporting=false
    if not ok then print('[Toolbox] Circle travel: '..tostring(err)) end
end)
local appearancePendingUntil=0
local function appearanceCircle(c)
    for id,p in pairs(points) do
        if p.kind~='npc_repellent' and p.enabled and (c.x-p.center.x)^2+(c.y-p.center.y)^2<=p.radius^2 then return id end
    end
end
local function canCustomize()
    return not loggedOut and not appearanceEditing and not manager and not accessing and not C.busy() and not C.placing
        and not C.managing and C.canStart() and not IsNuiFocused() and GetGameTimer()>=appearancePendingUntil
end
local function openAppearance(id,faceCodes)
    if not canCustomize() then return end
    appearancePendingUntil=GetGameTimer()+2000
    if GetResourceState('illenium-appearance')~='started' then
        C.notify('illenium-appearance が起動していません。') return
    end
    local result=call('appearance',id)
    local p=points[id]
    local c=GetEntityCoords(PlayerPedId())
    if not result then return end
    if loggedOut or not p or not p.enabled or IsNuiFocused()
        or (c.x-p.center.x)^2+(c.y-p.center.y)^2>p.radius^2 or not C.canStart() then
        C.notify('初期キャラ設定を開ける状態ではありません。サークル内で立って操作してください。')
        return
    end
    hint(nil)
    if faceCodes then
        lib.registerContext({id='omnite_circle_face_codes',title='整形',options={
            {title='顔コードを発行',event='illenium-appearance:client:generateFaceCode'},
            {title='顔コードを読み込み',event='illenium-appearance:client:importFaceCode'},
        }})
        lib.showContext('omnite_circle_face_codes')
    else
        appearanceEditing=true
        local ok,err=pcall(function()
            exports['illenium-appearance']:startPlayerCustomization(function(appearance)
                appearanceEditing=false
                if appearance and not loggedOut then
                    TriggerServerEvent('illenium-appearance:server:saveAppearance',appearance)
                end
            end,{
                ped=true,headBlend=true,faceFeatures=true,headOverlays=true,components=true,props=true,
                componentConfig={masks=true,upperBody=true,lowerBody=true,bags=true,shoes=true,
                    scarfAndChains=true,bodyArmor=true,shirts=true,decals=true,jackets=true},
                propConfig={hats=true,glasses=true,ear=true,watches=true,bracelets=true},
                tattoos=false,enableExit=true,hasTracker=false,automaticFade=true,
            })
        end)
        if not ok then
            appearanceEditing=false
            print('[Toolbox] Character customization: '..tostring(err))
            C.notify('初期キャラ設定を開けませんでした。F8ログを確認してください。')
        end
    end
end
local function warningLines()
    local lines={}
    for _,w in pairs(warnings) do
        local seconds=math.max(0,math.ceil((w.deadline-GetGameTimer())/1000))
        lines[#lines+1]=(w.message:gsub('{seconds}',tostring(seconds)))..(' [%d秒]'):format(seconds)
    end
    return lines
end
CreateThread(function()
    while true do
        local wait=250
        local hints=warningLines()
        if not loggedOut then
            local c=GetEntityCoords(PlayerPedId())
            for id,p in pairs(points) do
                local d=#(c-vec3(p.center.x,p.center.y,p.center.z))
                if p.kind~='npc_repellent' and d<Config.Circles.markerDistance then
                    wait=0
                    DrawMarker(1,p.center.x,p.center.y,p.center.z-0.95,0,0,0,0,0,0,0.8,0.8,0.15,255,100,100,160,false,false,2,false,nil,nil,false)
                end
            end
            local appearanceId=appearanceCircle(c)
            local m=manager
            if m and m.capture then
                wait=0
                local p=m.draft
                -- Preview the selected radius on the ground while capturing.
                local center=m.capture=='center' and c or p.center
                for i=0,63 do
                    local a,b=i*math.pi/32,(i+1)*math.pi/32
                    DrawLine(center.x+math.cos(a)*p.radius,center.y+math.sin(a)*p.radius,center.z,
                        center.x+math.cos(b)*p.radius,center.y+math.sin(b)*p.radius,center.z,255,100,100,200)
                end
                hints={'[E] 現在地を指定 / [Esc] 戻る'}
                DisableControlAction(0,38,true) DisableControlAction(0,202,true)
                if IsDisabledControlJustPressed(0,202) then showDraft()
                elseif IsDisabledControlJustPressed(0,38) then
                    local key=m.capture
                    m.capture=nil
                    CreateThread(function()
                        local result=call('capture')
                        if manager~=m then return end
                        if result then m.draft[key]=result.point end
                        showDraft()
                    end)
                end

            elseif appearanceId and canCustomize() then
                wait=0
                hints[#hints+1]='[E] 初期キャラ設定を開く / [G] 顔コード'
                DisableControlAction(0,38,true)
                DisableControlAction(0,47,true)
                if IsDisabledControlJustPressed(0,38) then
                    CreateThread(function() openAppearance(appearanceId) end)
                elseif IsDisabledControlJustPressed(0,47) then
                    CreateThread(function() openAppearance(appearanceId,true) end)
                end
            end
        end
        hint(#hints>0 and table.concat(hints,'  \n') or nil)
        Wait(wait)
    end
end)
local function load()
    loggedOut=false
    local result=call('list')
    if result and not loggedOut then managementAdmin=result.admin==true update(result.points,result.bucket) end
end
CreateThread(load)
AddEventHandler('QBCore:Client:OnPlayerLoaded',load)
AddEventHandler('QBCore:Client:OnPlayerUnload',function()
    loggedOut=true
    appearanceEditing=false
    if travellingPed then FreezeEntityPosition(travellingPed,false) travellingPed=nil DoScreenFadeIn(0) end
    lib.hideContext(false) lib.closeInputDialog()
    finish() removeBlips() removeTargets()
    points,warnings={},{}
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    if manager or accessing then lib.hideContext(false) lib.closeInputDialog() end
    if travellingPed then FreezeEntityPosition(travellingPed,false) travellingPed=nil C.teleporting=false end
    finish() removeBlips() removeTargets()
    DoScreenFadeIn(0)
end)
