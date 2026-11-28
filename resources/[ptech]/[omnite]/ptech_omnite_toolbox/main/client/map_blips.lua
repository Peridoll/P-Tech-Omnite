local C=SeatingClient
local prefix='ptech_omnite_toolbox:mapblip:'
local blips={}
local loggedOut,stopped=false,false
local stateVersion=0
local function clear()
    for _,handle in pairs(blips) do RemoveBlip(handle) end
    blips={}
end
local function update(points)
    stateVersion=stateVersion+1
    clear()
    if loggedOut or stopped then return end
    for id,p in pairs(points or {}) do
        if p.enabled then
            local handle=AddBlipForCoord(p.coords.x+0.0,p.coords.y+0.0,p.coords.z+0.0)
            SetBlipSprite(handle,p.sprite)
            SetBlipColour(handle,p.colour)
            SetBlipScale(handle,p.scale+0.0)
            -- チェックありは距離に関係なくミニマップにも表示します。
            SetBlipAsShortRange(handle,p.minimap~=true)
            SetBlipDisplay(handle,p.minimap==true and 2 or 4)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(p.name)
            EndTextCommandSetBlipName(handle)
            blips[id]=handle
        end
    end
end
RegisterNetEvent(prefix..'state',update)
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok then
        C.notify('マップブリップのサーバー処理に接続できません。F8ログを確認してください。')
        print('[Omnite map blips] '..tostring(result)) return
    end
    if not result or not result.ok then C.notify(result and result.message or '処理に失敗しました。') return end
    return result
end
local menu
local function edit(p)
    local input=lib.inputDialog(p and 'マップブリップを編集' or 'マップブリップを設置',{
        {type='input',label='地図に表示する名前',default=p and p.name,required=true,minLength=1,maxLength=64},
        {type='number',label='アイコンID（Sprite）',default=p and p.sprite or Config.MapBlips.defaultSprite,required=true,min=1,max=65535,precision=0},
        {type='number',label='色ID（Colour）',default=p and p.colour or Config.MapBlips.defaultColour,required=true,min=0,max=255,precision=0},
        {type='number',label='大きさ',default=p and p.scale or Config.MapBlips.defaultScale,required=true,min=0.1,max=5.0,precision=2,step=0.1},
        {type='checkbox',label='ミニマップにも常時表示する',checked=p and p.minimap==true or false},
        {type='checkbox',label='有効化',checked=not p or p.enabled},
        {type='checkbox',label='現在地へ設置・移動する',checked=not p},
    })
    if not input or stopped then return end
    local result=call('save',{id=p and p.id,revision=p and p.revision,name=input[1],sprite=input[2],colour=input[3],scale=input[4],
        minimap=input[5]==true,shortRange=input[5]~=true,enabled=input[6]==true,relocate=input[7]==true})
    if result then C.notify('マップブリップを保存しました。') end
    menu()
end
menu=function()
    if stopped or loggedOut then return end
    local result=call('list',true)
    if not result or stopped or loggedOut then return end
    local options={{title='現在地にブリップを設置',icon='plus',onSelect=function() edit() end},
        {title='Config形式でコピー',icon='copy',onSelect=function()
            local lines={'Config.MapBlips.fixed = {'}
            local ids={} for id in pairs(result.points) do ids[#ids+1]=id end table.sort(ids)
            for _,id in ipairs(ids) do local p=result.points[id]
                lines[#lines+1]=('    {id=%q,name=%q,coords={x=%.4f,y=%.4f,z=%.4f},sprite=%d,colour=%d,scale=%.2f,minimap=%s,shortRange=%s,enabled=%s,bucket=%d},'):format(id,p.name,p.coords.x,p.coords.y,p.coords.z,p.sprite,p.colour,p.scale,tostring(p.minimap==true),tostring(p.minimap~=true),tostring(p.enabled),p.bucket)
            end
            lines[#lines+1]='}' C.copy(table.concat(lines,'\n'))
        end}}
    local entries={} for _,p in pairs(result.points) do entries[#entries+1]=p end
    table.sort(entries,function(a,b) if a.name==b.name then return a.id<b.id end return a.name<b.name end)
    for _,p in ipairs(entries) do
        local entry=p
        options[#options+1]={title=entry.name,description=('%s / アイコン%d / 色%d / %.2f倍'):format(entry.enabled and '有効' or '無効',entry.sprite,entry.colour,entry.scale),onSelect=function()
            lib.registerContext({id='omnite_map_blip_edit',title=entry.name,menu='omnite_map_blips',options={
                {title='設定・位置を編集',onSelect=function() edit(entry) end},
                {title='削除',icon='trash',onSelect=function()
                    if lib.alertDialog({header='ブリップを削除',content=entry.name..'を削除しますか？',cancel=true})=='confirm' then call('delete',entry.id,entry.revision) end
                    menu()
                end},
            }}) lib.showContext('omnite_map_blip_edit')
        end}
    end
    lib.registerContext({id='omnite_map_blips',title='マップブリップ管理',options=options})
    lib.showContext('omnite_map_blips')
end
C.openMapBlips=menu
local function load()
    loggedOut=false
    local version=stateVersion
    local result=call('list')
    if result and version==stateVersion and not stopped and not loggedOut then update(result.points) end
end
CreateThread(load)
AddEventHandler('QBCore:Client:OnPlayerLoaded',load)
AddEventHandler('QBCore:Client:OnPlayerUnload',function() loggedOut=true stateVersion=stateVersion+1 clear() end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    stopped=true stateVersion=stateVersion+1 clear()
end)
