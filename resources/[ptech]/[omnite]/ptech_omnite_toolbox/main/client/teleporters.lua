local C=SeatingClient
local prefix='ptech_omnite_toolbox:teleport:'
local points,bucket={},0
local manager,travelling
local showingText=false
local directions={a_to_b='A → B（一方通行）',b_to_a='B → A（一方通行）',both='A ↔ B（双方向）'}
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok or not result then C.notify('サーバーから応答がありません。') return end
    if not result.ok then C.notify(result.message or '操作できませんでした。') return end
    return result
end
local function hideText()
    if showingText then lib.hideTextUI() showingText=false end
end
local function text(message)
    lib.showTextUI(message) showingText=true
end
local function finish()
    if manager and manager.token then TriggerServerEvent(prefix..'cancel',manager.token) end
    manager=nil C.teleportManaging=false hideText()
end
local function pointLabel(p)
    if not p then return '未指定' end
    return ('%.2f, %.2f, %.2f / %.1f°'):format(p.x,p.y,p.z,p.heading)
end
local showDraft,showList
local function begin(id,revision)
    local m=manager
    local result=call('begin',id,revision)
    if manager~=m then return end
    if not result then return end
    m.token,m.name,m.direction,m.a,m.b=result.token,result.name,result.mode,result.a,result.b
    m.id,m.revision=id,revision
    showDraft()
end
showDraft=function()
    local m=manager
    if not m then return end
    m.capture=nil m.mode='draft' hideText()
    local function again() if manager==m then showDraft() end end
    local options={
        {title='名前',description=m.name~='' and m.name or '未入力',onSelect=function()
            local input=lib.inputDialog('テレポーターの名前',{{type='input',label='名前',default=m.name,required=true,minLength=1,maxLength=64}})
            if manager~=m then return end
            if input then m.name=input[1] end
            again()
        end},
        {title='通行方向',description=directions[m.direction],onSelect=function()
            local input=lib.inputDialog('通行方向',{{type='select',label='通行方向',required=true,default=m.direction,
                options={{value='a_to_b',label=directions.a_to_b},{value='b_to_a',label=directions.b_to_a},{value='both',label=directions.both}}}})
            if manager~=m then return end
            if input then m.direction=input[1] end
            again()
        end},
    }
    for _,side in ipairs({'a','b'}) do
        local key=side
        options[#options+1]={title='地点'..key:upper()..'を指定',description=pointLabel(m[key]),onSelect=function()
            if manager~=m then return end
            m.capture=key m.mode='capture'
            C.notify('指定したい場所へ徒歩で移動し、Eを押してください。向きも記録します。')
        end}
    end
    options[#options+1]={title='保存して設置',disabled=not m.a or not m.b or not m.name:match('%S'),onSelect=function()
        if manager~=m then return end
        local result=call('save',m.token,m.name,m.direction)
        if manager~=m then return end
        if result then finish() C.notify('テレポーターを保存しました。') else again() end
    end}
    if m.id then options[#options+1]={title='削除',onSelect=function()
        local confirm=lib.alertDialog({header='テレポーターを削除',content=m.name..' を削除しますか？',cancel=true})
        if manager~=m then return end
        if confirm=='confirm' and call('delete',m.id,m.revision) then finish() C.notify('削除しました。') else again() end
    end} end
    options[#options+1]={title='キャンセル',onSelect=finish}
    lib.registerContext({id='omnite_teleport_draft',title=m.id and 'テレポーターの編集' or 'テレポーターの設置',options=options,onExit=finish})
    lib.showContext('omnite_teleport_draft')
end
showList=function()
    local m=manager
    if not m then return end
    local result=call('list')
    if manager~=m then return end
    if not result then finish() return end
    points,bucket=result.points,result.bucket
    m.bucket=bucket
    local entries={}
    for _,p in pairs(points) do entries[#entries+1]=p end
    table.sort(entries,function(a,b) if a.name==b.name then return tonumber(a.id)<tonumber(b.id) end return a.name<b.name end)
    local options={{title='新しいテレポーターを設置',description='AとBの2地点を指定します',onSelect=function() begin() end}}
    for _,p in ipairs(entries) do
        local entry=p
        options[#options+1]={title=entry.name,description=directions[entry.mode]..' / ID '..entry.id,onSelect=function() begin(entry.id,entry.revision) end}
    end
    lib.registerContext({id='omnite_teleport_list',title='テレポーターの管理',options=options,onExit=finish})
    lib.showContext('omnite_teleport_list')
end
function C.openTeleporters()
    if manager or C.busy() or C.placing or C.managing or not C.canStart() then return end
    -- 工具箱所持を再確認する。保存・座標採取・削除もサーバーで再確認する。
    local ok,auth=pcall(lib.callback.await,'ptech_omnite_seating:tool',false)
    if not ok or not auth or not auth.ok then C.notify('工具箱を所持した状態で開いてください。') return end
    if manager or C.busy() or C.placing or C.managing then return end
    manager={mode='list'} C.teleportManaging=true
    showList()
end
RegisterNetEvent(prefix..'state',function(state,newBucket)
    points,bucket=state or {},newBucket or 0
    if manager and manager.bucket and manager.bucket~=bucket then finish() end
    if manager then manager.bucket=bucket end
end)

local function travel(entry)
    if travelling or manager or C.busy() or C.placing or C.managing or not C.canStart() then return end
    local p=points[entry.id]
    if not p or p.revision~=entry.revision then C.notify('登録情報が更新されています。選び直してください。') return end
    travelling={} local trip=travelling
    C.teleporting=true hideText()
    local result=call('use',entry.id,entry.side,entry.revision)
    if travelling~=trip then return end
    if not result then travelling=nil C.teleporting=false return end
    local ped=PlayerPedId()
    local origin,heading=GetEntityCoords(ped),GetEntityHeading(ped)
    trip.ped=ped
    trip.origin,trip.heading=origin,heading
    local moved=false
    local ok,err=xpcall(function()
        DoScreenFadeOut(250)
        local deadline=GetGameTimer()+1000
        while not IsScreenFadedOut() and GetGameTimer()<deadline and travelling==trip do Wait(0) end
        if travelling~=trip then return end
        if IsPedDeadOrDying(ped,true) or IsPedInAnyVehicle(ped,false) then error('移動できる状態ではありません。') end
        local d=result.destination
        FreezeEntityPosition(ped,true)
        RequestCollisionAtCoord(d.x,d.y,d.z)
        SetEntityCoordsNoOffset(ped,d.x,d.y,d.z,false,false,false)
        moved=true
        trip.moved=true
        SetEntityHeading(ped,d.heading)
        deadline=GetGameTimer()+5000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer()<deadline and travelling==trip do
            RequestCollisionAtCoord(d.x,d.y,d.z) Wait(0)
        end
        if travelling==trip and not HasCollisionLoadedAroundEntity(ped) then error('移動先を読み込めませんでした。') end
    end,debug.traceback)
    if not ok and moved then
        SetEntityCoordsNoOffset(ped,origin.x,origin.y,origin.z,false,false,false)
        SetEntityHeading(ped,heading)
    end
    FreezeEntityPosition(ped,false)
    DoScreenFadeIn(250)
    if travelling==trip then travelling=nil C.teleporting=false end
    if not ok then print('[Toolbox] '..tostring(err)) C.notify('移動に失敗したため元の位置へ戻しました。') end
end
local function access(entries)
    if #entries==1 then travel(entries[1]) return end
    local options={}
    table.sort(entries,function(a,b) return a.distance<b.distance end)
    for _,p in ipairs(entries) do
        local entry=p
        options[#options+1]={title=entry.name,description=('%s → %s / %.2fm'):format(entry.side:upper(),entry.side=='a' and 'B' or 'A',entry.distance),
            onSelect=function() travel(entry) end}
    end
    lib.registerContext({id='omnite_teleport_access',title='移動先を選択',options=options})
    lib.showContext('omnite_teleport_access')
end
local nearby={}
CreateThread(function()
    while true do
        local p=GetEntityCoords(PlayerPedId())
        local result={}
        for id,entry in pairs(points) do
            if entry.bucket==bucket then
                for _,side in ipairs({'a','b'}) do
                    if (side=='a' and entry.mode~='b_to_a') or (side=='b' and entry.mode~='a_to_b') then
                        local c=entry[side]
                        if #(p-vec3(c.x,c.y,c.z))<Config.Teleporters.markerDistance then
                            result[#result+1]={id=id,revision=entry.revision,side=side,name=entry.name,coords=c}
                        end
                    end
                end
            end
        end
        nearby=result
        Wait(500)
    end
end)
CreateThread(function()
    while true do
        local m=manager
        if m and m.mode=='capture' then
            if IsPedDeadOrDying(PlayerPedId(),true) or IsPedInAnyVehicle(PlayerPedId(),false) then
                m.capture=nil showDraft()
            else
                local pos=GetEntityCoords(PlayerPedId())
                for _,side in ipairs({'a','b'}) do
                    local c=m[side]
                    if c and #(pos-vec3(c.x,c.y,c.z))<Config.Teleporters.markerDistance then
                        DrawMarker(1,c.x,c.y,c.z-0.95,0,0,0,0,0,0,0.65,0.65,0.12,80,180,255,160,false,false,2,false,nil,nil,false)
                        C.drawText(vec3(c.x,c.y,c.z+0.3),'地点'..side:upper())
                    end
                end
                text('地点'..m.capture:upper()..'の指定 | E：現在地と向きを記録 / Esc：戻る')
                DisableControlAction(0,38,true) DisableControlAction(0,202,true)
                if IsDisabledControlJustPressed(0,202) then showDraft()
                elseif IsDisabledControlJustPressed(0,38) then
                    local side=m.capture
                    local result=call('capture',m.token,side)
                    if manager==m then if result then m[side]=result.point end showDraft() end
                end
            end
            Wait(0)
        elseif not m and not travelling and not C.busy() and not C.placing and not C.managing and C.canStart() and #nearby>0 then
            local p=GetEntityCoords(PlayerPedId())
            local choices={}
            for _,entry in ipairs(nearby) do
                local current=points[entry.id]
                if current and current.revision==entry.revision then
                    local c=entry.coords
                    local distance=#(p-vec3(c.x,c.y,c.z))
                    if distance<Config.Teleporters.markerDistance then
                        DrawMarker(1,c.x,c.y,c.z-0.95,0,0,0,0,0,0,0.65,0.65,0.12,80,180,255,160,false,false,2,false,nil,nil,false)
                        C.drawText(vec3(c.x,c.y,c.z+0.3),entry.name..' / '..entry.side:upper())
                        if distance<=Config.Teleporters.interactDistance then
                            choices[#choices+1]={id=entry.id,revision=entry.revision,side=entry.side,name=entry.name,distance=distance}
                        end
                    end
                end
            end
            if #choices>0 then
                text('E：テレポート'..(#choices>1 and '先を選択' or ''))
                DisableControlAction(0,38,true)
                if IsDisabledControlJustPressed(0,38) then hideText() access(choices) end
            else hideText() end
            Wait(0)
        else hideText() Wait(200) end
    end
end)
CreateThread(function()
    local ok,result=pcall(lib.callback.await,prefix..'list',false)
    if ok and result and result.ok then points,bucket=result.points,result.bucket end
end)
local function abortTravel()
    if travelling then
        if travelling.ped then
            if travelling.moved and not HasCollisionLoadedAroundEntity(travelling.ped) then
                local c=travelling.origin
                SetEntityCoordsNoOffset(travelling.ped,c.x,c.y,c.z,false,false,false)
                SetEntityHeading(travelling.ped,travelling.heading)
            end
            FreezeEntityPosition(travelling.ped,false) DoScreenFadeIn(0)
        end
        travelling=nil C.teleporting=false
    end
end
AddEventHandler('QBCore:Client:OnPlayerUnload',function() finish() abortTravel() end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    finish() abortTravel()
end)
