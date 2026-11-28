local prefix='ptech_omnite_toolbox:atm:'
local points,objects={},{}
local function notify(text) lib.notify({description=text}) end
local function clear(id)
    if objects[id] and DoesEntityExist(objects[id]) then DeleteEntity(objects[id]) end
    objects[id]=nil
end
RegisterNetEvent(prefix..'state',function(data)
    for id in pairs(objects) do clear(id) end
    points=data or {}
end)
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok then
        notify('ATMのサーバー処理に接続できません。F8の[Omnite ATM]ログを確認してください。')
        print(('[Omnite ATM] Callback %s failed: %s'):format(action,tostring(result)))
        return
    end
    if not result or not result.ok then notify(result and result.message or '処理に失敗しました。') return end
    return result
end
local menu
local function edit(p)
    local models={} for _,model in ipairs(Config.ATMs.models) do models[#models+1]={label=model,value=model} end
    local input=lib.inputDialog('ATMの設置',{
        {type='input',label='名前',required=true,default=p and p.name,max=64},
        {type='select',label='ATMモデル',options=models,required=true,default=p and p.model or Config.ATMs.models[1]},
        {type='checkbox',label='現在地へ配置する',checked=not p},
        {type='number',label='足元からの高さ（m）',default=0,precision=2,min=-2,max=2,required=true},
    })
    if not input then return end
    local ped=PlayerPedId() local c=GetEntityCoords(ped)
    call('save',{id=p and p.id,revision=p and p.revision,name=input[1],model=input[2],relocate=input[3]==true,
        coords={x=c.x,y=c.y,z=c.z-1.0+input[4]},heading=GetEntityHeading(ped)})
    menu()
end
menu=function()
    local result=call('list',true) if not result then return end
    local options={{title='現在地にATMを設置',icon='plus',onSelect=function() edit() end},
        {title='Config形式でコピー',icon='copy',onSelect=function()
            local lines={'Config.ATMs.fixed = {'}
            for id,p in pairs(result.points) do lines[#lines+1]=('    {id=%q,name=%q,model=%q,coords={x=%.4f,y=%.4f,z=%.4f},heading=%.2f,bucket=%d},'):format(id,p.name,p.model,p.coords.x,p.coords.y,p.coords.z,p.heading,p.bucket) end
            lines[#lines+1]='}'
            SendNUIMessage({action='copyText',text=table.concat(lines,'\n')}) SetNuiFocus(true,true)
        end}}
    for _,value in pairs(result.points) do
        local p=value
        options[#options+1]={title=p.name,description=p.model,onSelect=function()
            lib.registerContext({id='omnite_atm_edit',title=p.name,menu='omnite_atms',options={
                {title='設定・位置を編集',onSelect=function() edit(p) end},
                {title='削除',icon='trash',onSelect=function()
                    if lib.alertDialog({header='ATMを削除',content=p.name..'を削除しますか？',cancel=true})=='confirm' then call('delete',p.id,p.revision) end
                    menu()
                end},
            }}) lib.showContext('omnite_atm_edit')
        end}
    end
    lib.registerContext({id='omnite_atms',title='ATM管理',options=options}) lib.showContext('omnite_atms')
end
SeatingClient.openATMs=menu
CreateThread(function()
    local result=call('list') if result then points=result.points end
    while true do
        local c=GetEntityCoords(PlayerPedId())
        for id,p in pairs(points) do
            if #(c-vec3(p.coords.x,p.coords.y,p.coords.z))<Config.ATMs.streamDistance then
                if not objects[id] then
                    local hash=joaat(p.model)
                    if IsModelInCdimage(hash) and IsModelValid(hash) then
                        RequestModel(hash)
                        local deadline=GetGameTimer()+3000
                        while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
                        if HasModelLoaded(hash) and points[id]==p then
                            local entity=CreateObjectNoOffset(hash,p.coords.x,p.coords.y,p.coords.z,false,false,false)
                            if entity~=0 then SetEntityHeading(entity,p.heading) FreezeEntityPosition(entity,true) SetEntityAsMissionEntity(entity,true,true) objects[id]=entity end
                        end
                        SetModelAsNoLongerNeeded(hash)
                    end
                end
            else clear(id) end
        end
        Wait(500)
    end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() then for id in pairs(objects) do clear(id) end end
end)
