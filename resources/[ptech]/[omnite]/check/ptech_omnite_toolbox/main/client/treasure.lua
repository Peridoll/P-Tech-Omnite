local C=SeatingClient
local prefix='ptech_omnite_toolbox:treasure:'
local points,npcs,errors={},{},{}
local stopped,loggedOut,claiming=false,false,false
local stateVersion=0
local function notify(message) lib.notify({description=message}) end
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok then print('[Omnite treasure] '..tostring(result)) notify('宝箱NPCの処理に接続できません。') return end
    if not result or not result.ok then notify(result and result.message or '処理に失敗しました。') return end
    return result
end
local function clear(id)
    local entry=npcs[id]
    npcs[id]=nil
    if entry and entry.entity then
        pcall(function() exports.ox_target:removeLocalEntity(entry.entity) end)
        if DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    end
end
local function update(list)
    if stopped or loggedOut or type(list)~='table' then return end
    stateVersion=stateVersion+1
    for id in pairs(points) do if not list[id] or json.encode(points[id])~=json.encode(list[id]) then clear(id) end end
    points=list
end
RegisterNetEvent(prefix..'state',update)
local function load()
    local version=stateVersion
    local result=call('list')
    if result and version==stateVersion and not loggedOut and not stopped then update(result.points) end
end
local function spawn(id,p)
    local entry={loading=true}
    npcs[id]=entry
    CreateThread(function()
        local model
        local ok,err=pcall(function()
            model=lib.requestModel(p.model,5000)
            if stopped or loggedOut or npcs[id]~=entry or points[id]~=p or not p.enabled then return end
            local c=vec3(p.coords.x,p.coords.y,p.coords.z)
            if #(GetEntityCoords(PlayerPedId())-c)>=80 then return end
            local ped=CreatePed(4,model,c.x,c.y,c.z,p.heading,false,true)
            if ped==0 or not DoesEntityExist(ped) then error('CreatePed returned no entity') end
            entry.entity=ped
            SetEntityAsMissionEntity(ped,true,true)
            SetEntityCoordsNoOffset(ped,c.x,c.y,c.z,false,false,false)
            SetEntityInvincible(ped,true)
            SetEntityCanBeDamaged(ped,false)
            SetPedCanRagdoll(ped,false)
            FreezeEntityPosition(ped,true)
            SetBlockingOfNonTemporaryEvents(ped,true)
            exports.ox_target:addLocalEntity(ped,{{name=prefix..id,label='報酬を受け取る',icon='fa-solid fa-gift',distance=Config.Treasure.interactDistance,
                canInteract=function() return not claiming and not stopped and not loggedOut and points[id] and points[id].enabled end,
                onSelect=function()
                    if claiming or stopped or loggedOut then return end
                    claiming=true
                    local result=call('claim',id)
                    claiming=false
                    if result then notify(result.message or '報酬を受け取りました！') end
                end,
            }})
            errors[id]=nil
        end)
        if model then SetModelAsNoLongerNeeded(model) end
        entry.loading=false
        if npcs[id]==entry and (not ok or not entry.entity) then clear(id) end
        if not ok and not stopped then
            local message=tostring(err)
            if errors[id]~=message then print(('[Omnite treasure] NPC %s: %s'):format(id,message)) end
            errors[id]=message
        end
    end)
end
local menu
local function edit(p)
    local input=lib.inputDialog(p and '宝箱NPCを編集' or '宝箱NPCを設置',{
        {type='input',label='管理用の名前',default=p and p.name,required=true,minLength=1,maxLength=64},
        {type='input',label='NPCモデル名',default=p and p.model or Config.Treasure.model,required=true,maxLength=100},
        {type='checkbox',label='報酬受取を有効にする',checked=p and p.enabled or false},
        {type='checkbox',label='現在地へ設置・移動する',checked=not p},
    })
    if not input then return end
    local hash=joaat(input[2])
    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then notify('有効なNPCモデル名を入力してください。') return end
    if call('save',{id=p and p.id,revision=p and p.revision,name=input[1],model=input[2],enabled=input[3]==true,relocate=input[4]==true}) then notify('宝箱NPCを保存しました。') end
    menu()
end
local function reviews(p)
    local result=call('reviews',p.id) if not result then return end
    local options={}
    for _,row in ipairs(result.claims) do
        local record=row
        local rewards=json.decode(record.payload)
        local index=tonumber(record.next_index)
        local reward=rewards[index]
        options[#options+1]={title=record.display_name..' / '..record.citizenid,
            description=('%s × %d の配布結果が未確定'):format(reward.name,reward.count),onSelect=function()
                local function resolve(delivered)
                    local content=delivered and '実際の所持品やログを確認し、この品目を配布済みとして確定しますか？' or '実際の所持品やログを確認し、この品目を未配布として再受取可能にしますか？'
                    if lib.alertDialog({header='受取記録を確定',content=content,cancel=true})=='confirm' then call('resolve',p.id,record.citizenid,index,delivered) end
                    reviews(p)
                end
                lib.registerContext({id='omnite_treasure_review_item',title=record.display_name,options={
                    {title='この品目は渡し済み',onSelect=function() resolve(true) end},
                    {title='この品目は未配布・再受取を許可',onSelect=function() resolve(false) end},
                }}) lib.showContext('omnite_treasure_review_item')
            end}
    end
    if #options==0 then options[1]={title='未確定の記録はありません',disabled=true} end
    lib.registerContext({id='omnite_treasure_reviews',title='未確定の受取を確認',options=options}) lib.showContext('omnite_treasure_reviews')
end
menu=function()
    if stopped or loggedOut then return end
    local result=call('list',true) if not result then return end
    local options={{title='現在地に宝箱NPCを設置',icon='plus',onSelect=function() edit() end}}
    local entries={} for _,p in pairs(result.points) do entries[#entries+1]=p end
    table.sort(entries,function(a,b) return a.name<b.name end)
    for _,p in ipairs(entries) do
        local point=p
        options[#options+1]={title=point.name,description=point.enabled and '受取可能' or '停止中',onSelect=function()
            lib.registerContext({id='omnite_treasure_edit',title=point.name,menu='omnite_treasures',options={
                {title='NPCの設定・位置を編集',onSelect=function() edit(point) end},
                {title='報酬スタッシュを開く',description='NPCの近くで開きます。中身と数量が1人分の報酬セットです。見本は配布で消費しません。',onSelect=function()
                    local opened=call('stash',point.id)
                    if opened then exports.ox_inventory:openInventory('stash',opened.inventory) end
                end},
                {title='未確定の受取を確認',description='配布中の切断・障害などで、結果を確認できなかった記録を確認します。',onSelect=function() reviews(point) end},
                {title='NPCを削除',icon='trash',onSelect=function()
                    if lib.alertDialog({header='宝箱NPCを削除',content=point.name..'を削除しますか？先に報酬スタッシュを空にしてください。',cancel=true})=='confirm' then call('delete',point.id,point.revision) end
                    menu()
                end},
            }}) lib.showContext('omnite_treasure_edit')
        end}
    end
    lib.registerContext({id='omnite_treasures',title='宝箱NPC管理',options=options}) lib.showContext('omnite_treasures')
end
C.openTreasures=menu
CreateThread(function()
    Wait(1500) load()
    while not stopped do
        if not loggedOut then
            local here=GetEntityCoords(PlayerPedId())
            for id,p in pairs(points) do
                local entry=npcs[id]
                if entry and entry.entity and (not DoesEntityExist(entry.entity) or IsPedDeadOrDying(entry.entity,true)) then clear(id) end
                local distance=#(here-vec3(p.coords.x,p.coords.y,p.coords.z))
                if not p.enabled or distance>100 then clear(id)
                elseif distance<80 and not npcs[id] then spawn(id,p) end
            end
        end
        Wait(1000)
    end
end)
AddEventHandler('QBCore:Client:OnPlayerLoaded',function() loggedOut=false load() end)
AddEventHandler('QBCore:Client:OnPlayerUnload',function()
    loggedOut=true stateVersion=stateVersion+1
    for id in pairs(npcs) do clear(id) end points={}
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    stopped=true stateVersion=stateVersion+1
    for id in pairs(npcs) do clear(id) end points={}
end)
