local draft,busy,selecting
local fields={personal='GarageLocations',public='GarageLocations',job='JobGarageLocations',gang='GangGarageLocations',impound='ImpoundLocations'}
local function notify(text) lib.notify({description=text}) end
local function authorize()
    local ok,result=pcall(lib.callback.await,'ptech_omnite_garages:authorize',false)
    if not ok or not result then notify('Omini工具箱を所持してください。') return false end
    return true
end
local function point(data)
    return {x=data.x,y=data.y,z=data.z,w=data.w or 0}
end
local function capture()
    selecting=true
    lib.showTextUI('ガレージ位置指定 | 移動してEで確定 / Escで中止（出庫位置は車に乗って指定できます）')
    while selecting do
        DisableControlAction(0,38,true) DisableControlAction(0,202,true)
        if IsDisabledControlJustPressed(0,202) then break end
        if IsPedDeadOrDying(PlayerPedId(),true) then break end
        if IsDisabledControlJustPressed(0,38) then
            local ped=PlayerPedId()
            local vehicle=GetVehiclePedIsIn(ped,false)
            local entity=vehicle~=0 and vehicle or ped
            local coords=GetEntityCoords(entity)
            local captured={x=coords.x,y=coords.y,z=coords.z,w=GetEntityHeading(entity)}
            selecting=false lib.hideTextUI()
            return captured
        end
        Wait(0)
    end
    selecting=false lib.hideTextUI()
end
local function exportText()
    if not draft or not draft.entry or #draft.spawns==0 then notify('受付位置と、1つ以上の出庫位置が必要です。') return end
    local base=('Config.%s[%q]'):format(draft.field,draft.name)
    local c=draft.entry
    local lines={
        '-- 同名の既存ガレージを更新します。JG config/config.luaの該当テーブル定義より後に追加してください。',
        ('%s.coords = vector3(%.4f, %.4f, %.4f)'):format(base,c.x,c.y,c.z),
        base..'.spawn = {',
    }
    for _,p in ipairs(draft.spawns) do lines[#lines+1]=('    vector4(%.4f, %.4f, %.4f, %.2f),'):format(p.x,p.y,p.z,p.w) end
    lines[#lines+1]='}'
    local text=table.concat(lines,'\n')
    if pcall(function() lib.setClipboard(text) end) then notify('Config用の位置設定をコピーしました。反映後にJGを再起動してください。')
    else lib.inputDialog('設定行を選択してコピー',{{type='textarea',label='Config出力',default=text,min=8,max=18}}) end
end
local showDraft
local function numeric(p,heading)
    local rows={{type='number',label='X',default=p.x,required=true,precision=4},{type='number',label='Y',default=p.y,required=true,precision=4},{type='number',label='Z',default=p.z,required=true,precision=4}}
    if heading then rows[#rows+1]={type='number',label='向き（度）',default=p.w,required=true,min=0,max=360,precision=2} end
    local values=lib.inputDialog('位置を数値で編集',rows)
    if values then return {x=values[1],y=values[2],z=values[3],w=heading and values[4]%360 or p.w} end
end
showDraft=function()
    if not draft then return end
    lib.registerContext({id='omnite_garage_draft',title='ガレージの場所：'..draft.name,options={
        {title='受付位置を指定',description='現地へ移動してEで確定',onSelect=function()
            if authorize() then draft.entry=capture() or draft.entry end showDraft()
        end},
        {title='受付位置を数値で編集',onSelect=function() draft.entry=numeric(draft.entry,false) or draft.entry showDraft() end},
        {title='出庫位置を追加',description=('現在%d地点 / 最大%d地点'):format(#draft.spawns,Config.maxSpawnPoints),disabled=#draft.spawns>=Config.maxSpawnPoints,onSelect=function()
            if authorize() then local p=capture() if p then draft.spawns[#draft.spawns+1]=p end end showDraft()
        end},
        {title='出庫位置を編集・削除',onSelect=function()
            local options={}
            for i,p in ipairs(draft.spawns) do
                local index=i
                options[#options+1]={title=('出庫位置 %d'):format(index),description=('%.2f, %.2f, %.2f / %.1f°'):format(p.x,p.y,p.z,p.w),onSelect=function()
                    lib.registerContext({id='omnite_garage_point',title='出庫位置 '..index,menu='omnite_garage_draft',options={
                        {title='現地で取り直す',onSelect=function() if authorize() then draft.spawns[index]=capture() or draft.spawns[index] end showDraft() end},
                        {title='数値で編集',onSelect=function() draft.spawns[index]=numeric(draft.spawns[index],true) or draft.spawns[index] showDraft() end},
                        {title='この出庫位置を削除',onSelect=function() table.remove(draft.spawns,index) showDraft() end},
                    }}) lib.showContext('omnite_garage_point')
                end}
            end
            lib.registerContext({id='omnite_garage_points',title='出庫位置',menu='omnite_garage_draft',options=options}) lib.showContext('omnite_garage_points')
        end},
        {title='Config形式でコピー',description='既存の出庫位置一覧を、この一覧で置き換える設定を出力します',onSelect=function() if authorize() then exportText() end showDraft() end},
    }}) lib.showContext('omnite_garage_draft')
end
exports('openManager',function()
    if busy or selecting then return end
    busy=true
    local ok,err=pcall(function()
        if not authorize() then return end
        local version=GetResourceMetadata(Config.garageResource,'version',0) or ''
        if not version:match('^v?3%.') then notify('この位置指定ツールはJG Advanced Garages v3用です。') return end
        local locations=lib.callback.await('jg-advancedgarages:server:get-available-garage-locations',false)
        local options={}
        for name,garage in pairs(locations or {}) do
            local id,data=name,garage
            local field=fields[data.garageType or 'public']
            if field and data.coords then options[#options+1]={title=id,onSelect=function()
                local spawns={}
                if data.spawn then
                    if data.spawn.x then spawns[1]=point(data.spawn)
                    else for _,p in ipairs(data.spawn) do spawns[#spawns+1]=point(p) end end
                end
                draft={name=id,field=field,entry=point(data.coords),spawns=spawns}
                showDraft()
            end} end
        end
        table.sort(options,function(a,b) return a.title<b.title end)
        if #options==0 then notify('選択できる既存ガレージがありません。') return end
        lib.registerContext({id='omnite_garage_locations',title='場所を変更するガレージ',options=options}) lib.showContext('omnite_garage_locations')
    end)
    busy=false
    if not ok then notify('ガレージ情報を取得できませんでした。F8を確認してください。') print('[Omnite garages] '..tostring(err)) end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    if selecting then selecting=false lib.hideTextUI() end
    pcall(function()
        local context=lib.getOpenContextMenu()
        if context and context:match('^omnite_garage_') then lib.hideContext(false) end
    end)
end)
