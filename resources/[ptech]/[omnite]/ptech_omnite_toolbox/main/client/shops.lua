local prefix='ptech_omnite_shops:'
local shops,entities,zones={},{},{}
local isManager=false
local availableJobs={}
local function jobNames(p,field)
    return p and (p[field..'s'] or (p[field] and {p[field]})) or {}
end
local function hasJob(p,name)
    for _,entry in ipairs(jobNames(p,'stockJob')) do if entry==name then return true end end
    return false
end
local function jobOptions(p)
    local options,seen={},{}
    for name,job in pairs(availableJobs) do
        options[#options+1]={value=name,label=(job.label or name)..' ('..name..')'} seen[name]=true
    end
    for _,field in ipairs({'purchaseJob','stockJob'}) do
        for _,name in ipairs(jobNames(p,field)) do
            if not seen[name] then options[#options+1]={value=name,label=name} seen[name]=true end
        end
    end
    for _,name in ipairs(p and p.vaultAccess and p.vaultAccess.jobs or {}) do
        if not seen[name] then options[#options+1]={value=name,label=name} seen[name]=true end
    end
    table.sort(options,function(a,b) return a.value<b.value end)
    return options
end
local stopped,loggedOut=false,false
local stateVersion=0
local spawnErrors={}
local loading,approached={},{}
local refreshRequested=false
local streaming={}
for key,value in pairs({spawnDistance=80.0,despawnDistance=100.0,refreshInterval=15000,refreshCooldown=3000,retryInterval=5000,modelTimeout=5000}) do
    streaming[key]=(Config.ShopStreaming and Config.ShopStreaming[key]) or value
end
local function notify(message) lib.notify({description=message}) end
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok or not result then notify('ショップの処理に失敗しました。') return end
    if not result.ok then notify(result.message) return end
    return result
end
local function inventory(id,kind)
    local result=call('inventory',id,kind)
    if result then exports.ox_inventory:openInventory('stash',result.inventory) end
end
local managerMenu,products
products=function(p)
    local result=call('products',p.id) if not result then return end
    local options={{title='商品を登録・補充する',description='商品スタッシュを開き、販売するアイテムを入れます。閉じた後、この一覧を開き直してください。',onSelect=function() inventory(p.id,'stock') end}}
    for _,entry in ipairs(result.products) do
        local item=entry
        options[#options+1]={title=item.label,description=('%s / %d個 / %s / $%d'):format(item.name,item.count,item.enabled and '販売可' or '販売不可',item.price),onSelect=function()
            local input=lib.inputDialog(item.label,{
                {type='checkbox',label='販売可（初期値は不可）',checked=item.enabled},
                {type='number',label='現金販売額',default=item.price,min=0,max=100000000,precision=0,required=true},
            })
            if input then call('product',p.id,{slot=item.slot,key=item.key,revision=result.revision,enabled=input[1]==true,price=input[2]}) end
            products(p)
        end}
    end
    if #result.products==0 then options[#options+1]={title='登録された商品はありません',description='「商品を登録・補充する」からアイテムを入れてください。',disabled=true} end
    lib.registerContext({id='omnite_shop_products',title=p.name..' 商品リスト・販売価格',options=options})
    lib.showContext('omnite_shop_products')
end
local function purchaseGrades(p,names,title,permission)
    if #names==0 then return {} end
    local rows={}
    for _,name in ipairs(names) do
        local job=availableJobs[name]
        local minimum=p and p.purchaseGrades and p.purchaseGrades[name] or 0
        local options={}
        for level,grade in pairs(job and job.grades or {}) do
            if tonumber(level) then options[#options+1]={value=tostring(level),label=('%s（階級%d）以上'):format(grade.name or tostring(level),tonumber(level))} end
        end
        table.sort(options,function(a,b) return tonumber(a.value)<tonumber(b.value) end)
        if #options>0 then
            local found=false
            for _,option in ipairs(options) do if tonumber(option.value)==minimum then found=true end end
            if not found then options[#options+1]={value=tostring(minimum),label=('階級%d以上（保存済み）'):format(minimum)} end
            rows[#rows+1]={type='select',label=(job.label or name)..'：'..(permission or '購入可能な最低階級'),options=options,default=tostring(minimum),required=true}
        else
            rows[#rows+1]={type='number',label=name..'：購入可能な最低階級',default=minimum,min=0,max=100000,precision=0,required=true}
        end
    end
    local input=lib.inputDialog(title or 'JOB別の販売可能階級',rows)
    if not input then return end
    local result={}
    for i,name in ipairs(names) do result[name]=tonumber(input[i]) end
    return result
end
local function edit(p)
    local options=jobOptions(p)
    local input=lib.inputDialog(p and 'ショップを編集' or 'ショップを設置',{
        {type='input',label='ショップ名',default=p and p.name,required=true,maxLength=64},
        {type='checkbox',label='NPCを配置する',checked=not p or p.model~=false},
        {type='input',label='NPCモデル名',default=p and p.model or 's_m_m_dockwork_01',maxLength=100},
        {type='checkbox',label='有限在庫モード',checked=not p or p.finite},
        {type='checkbox',label='購入JOB制限を設定する',checked=#jobNames(p,'purchaseJob')>0},
        {type='multi-select',label='購入可能なJOB（複数選択可）',options=options,default=jobNames(p,'purchaseJob'),searchable=true},
        {type='multi-select',label='在庫管理JOB（未選択はadminのみ）',options=options,default=jobNames(p,'stockJob'),searchable=true},
        {type='checkbox',label='自分の足元・向きへ配置する',checked=not p},
    })
    if not input then return end
    if input[5] and (not input[6] or #input[6]==0) then notify('購入可能なJOBを選択してください。') return end
    if input[2] and (not input[3] or not IsModelInCdimage(joaat(input[3])) or not IsModelAPed(joaat(input[3]))) then notify('有効なNPCモデル名を入力してください。') return end
    local selectedJobs=input[5] and input[6] or {}
    local grades=purchaseGrades(p,selectedJobs)
    if not grades then return end
    local ped=PlayerPedId()
    local c=GetEntityCoords(ped)
    local heading=GetEntityHeading(ped)
    call('save',{id=p and p.id,revision=p and p.revision,name=input[1],model=input[2] and input[3] or false,
        finite=input[4]==true,purchaseJobs=selectedJobs,purchaseGrades=grades,stockJobs=input[7] or {},
        relocate=input[8]==true,coords={x=c.x,y=c.y,z=c.z},heading=heading,coordinateMode='origin'})
    managerMenu()
end
local function editGrades(p)
    local names=jobNames(p,'purchaseJob')
    if #names==0 then
        notify('先にショップ設定で購入JOB制限を有効にし、購入可能なJOBを選択してください。')
        return
    end
    local grades=purchaseGrades(p,names)
    if not grades then return end
    local result=call('save',{id=p.id,revision=p.revision,name=p.name,model=p.model,
        finite=p.finite,purchaseJobs=names,purchaseGrades=grades,stockJobs=jobNames(p,'stockJob'),
        relocate=false,coords=p.coords,heading=p.heading})
    if result then notify('JOB別の販売可能階級を保存しました。') managerMenu() end
end
local function editVaultAccess(p)
    local access=p.vaultAccess
    local input=lib.inputDialog('金庫の利用権限',{
        {type='checkbox',label='在庫管理JOBの店長のみ（従来の設定）',checked=access==nil},
        {type='multi-select',label='金庫を開けるJOB（複数選択可）',description='個別設定時は未選択だと誰も開けられません。',options=jobOptions(p),default=access and access.jobs or jobNames(p,'stockJob'),searchable=true},
        {type='checkbox',label='個別設定でも店長（isboss）のみにする',checked=access and access.bossOnly or false},
    })
    if not input then return end
    local names=input[2] or {}
    local grades={}
    if not input[1] then
        grades=purchaseGrades({purchaseGrades=access and access.grades or {}},names,'JOB別の金庫利用階級','金庫を開ける最低階級')
        if not grades then return end
    end
    local result=call('vaultAccess',p.id,{revision=p.revision,inherit=input[1]==true,jobs=names,grades=grades,bossOnly=input[3]==true})
    if result then notify('金庫の利用権限を保存しました。') managerMenu() end
end
local function targetOptions(p)
    local function stockAccess()
        local data=exports.qbx_core:GetPlayerData()
        return isManager or (data and data.job and hasJob(p,data.job.name)) or false
    end
    local function vaultAccess()
        local data=exports.qbx_core:GetPlayerData()
        local job=data and data.job
        local access=p.vaultAccess
        if not access then return job and hasJob(p,job.name) and job.isboss==true or false end
        if not job or (access.bossOnly and job.isboss~=true) then return false end
        for _,name in ipairs(access.jobs) do
            if name==job.name then
                local grade=type(job.grade)=='table' and job.grade.level or job.grade
                return (tonumber(grade) or 0)>=(access.grades[name] or 0)
            end
        end
        return false
    end
    return {
        {name=prefix..p.id,label=p.name..'を開く',icon='fa-solid fa-store',distance=2.5,onSelect=function()
            local result=call('open',p.id)
            if result then exports.ox_inventory:openInventory('shop',{type=result.shop}) end
        end},
        {name=prefix..p.id..':stock',label='在庫を補充する',icon='fa-solid fa-boxes-stacked',distance=2.5,
            canInteract=function() return p.finite and stockAccess() end,
            onSelect=function() inventory(p.id,'stock') end},
        {name=prefix..p.id..':sales',label='金庫を開く',icon='fa-solid fa-money-bill',distance=2.5,
            canInteract=vaultAccess,onSelect=function() inventory(p.id,'sales') end},
    }
end
local function clear(id)
    loading[id]=nil
    local ped=entities[id]
    entities[id]=nil
    if ped then
        pcall(function() exports.ox_target:removeLocalEntity(ped) end)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    local zone=zones[id]
    zones[id]=nil
    if zone then pcall(function() exports.ox_target:removeZone(zone) end) end
end
local function same(a,b)
    if a==b then return true end
    if type(a)~='table' or type(b)~='table' then return false end
    for key,value in pairs(a) do if not same(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local function update(list)
    if stopped or loggedOut or type(list)~='table' then return end
    stateVersion=stateVersion+1
    for id,p in pairs(shops) do
        if list[id] and same(p,list[id]) then list[id]=p
        else clear(id) approached[id]=nil end
    end
    shops=list
end
RegisterNetEvent(prefix..'state',update)
local function refresh(silent)
    local version=stateVersion
    local ok,result=pcall(lib.callback.await,prefix..'list',false)
    if not ok or not result or not result.ok or type(result.shops)~='table' then
        if silent~=true then notify(type(result)=='table' and result.message or 'ショップ情報を取得できませんでした。') end
        return false
    end
    if not stopped and not loggedOut and version==stateVersion then
        isManager=result.manager availableJobs=result.jobs or {} update(result.shops)
        return true
    end
    return false
end
managerMenu=function()
    refresh()
    if not isManager then notify('管理者権限と工具箱が必要です。') return end
    local options={{title='新しいショップを設置',onSelect=function() edit() end}}
    for _,point in pairs(shops) do
        local p=point
        options[#options+1]={title=p.name,description=(p.finite and '有限在庫' or '無限在庫')..' / '..(#jobNames(p,'purchaseJob')>0 and table.concat(jobNames(p,'purchaseJob'),', ') or '購入制限なし'),onSelect=function()
            lib.registerContext({id='omnite_shop_edit',title=p.name,menu='omnite_shops_manager',options={
                {title='ショップ設定・NPCモデル・位置を編集',onSelect=function() edit(p) end},
                {title='JOB別の販売可能階級',description='購入可能なJOBごとに、購入できる最低階級を設定します。',onSelect=function() editGrades(p) end},
                {title='商品登録・補充・レイアウト',onSelect=function() inventory(p.id,'stock') end},
                {title='商品リスト・販売価格',onSelect=function() products(p) end},
                {title='金庫を開く権限を設定',description='JOBごとの最低階級と、店長限定の有無を設定します。',onSelect=function() editVaultAccess(p) end},
                {title='金庫を開く',onSelect=function() inventory(p.id,'sales') end},
                {title='ショップを削除',description='商品と売上金を返却し、持てない分は足元へ落とします。',onSelect=function()
                    if lib.alertDialog({header='ショップを削除',content='商品・売上を回収して削除しますか？',cancel=true})=='confirm' then call('delete',p.id,p.revision) end
                    managerMenu()
                end},
            }}) lib.showContext('omnite_shop_edit')
        end}
    end
    lib.registerContext({id='omnite_shops_manager',title='ショップ管理',options=options}) lib.showContext('omnite_shops_manager')
end
SeatingClient.openShops=managerMenu
local function anchor(ped,p)
    -- 旧保存値はプレイヤー原点から1m引いた座標。DBを書き換えず表示時だけ戻します。
    local z=p.coords.z+(p.coordinateMode=='origin' and 0.0 or 1.0)
    SetEntityCoordsNoOffset(ped,p.coords.x,p.coords.y,z,false,false,false)
    SetEntityHeading(ped,p.heading)
    FreezeEntityPosition(ped,true)
end
local function spawn(id,p,c,options)
    local token={}
    loading[id]=token
    CreateThread(function()
        local model
        local ok,err=pcall(function()
            model=lib.requestModel(p.model,streaming.modelTimeout)
            if stopped or loggedOut or loading[id]~=token or shops[id]~=p or #(GetEntityCoords(PlayerPedId())-c)>=streaming.spawnDistance then return end
            local entity=CreatePed(4,model,c.x,c.y,c.z,p.heading,false,true)
            if entity==0 or not DoesEntityExist(entity) then error('CreatePed returned no entity') end
            entities[id]=entity
            SetEntityAsMissionEntity(entity,true,true)
            anchor(entity,p)
            SetEntityInvincible(entity,true)
            SetEntityCanBeDamaged(entity,false)
            SetPedCanRagdoll(entity,false)
            SetEntityVisible(entity,true,false)
            FreezeEntityPosition(entity,true)
            SetBlockingOfNonTemporaryEvents(entity,true)
            exports.ox_target:addLocalEntity(entity,options)
            spawnErrors[id]=nil
        end)
        if model then SetModelAsNoLongerNeeded(model) end
        if loading[id]~=token then return end
        loading[id]=nil
        if not ok then
            clear(id)
            local message=tostring(err)
            if spawnErrors[id]~=message then print(('[Omnite shops] NPC %s: %s'):format(id,message)) end
            spawnErrors[id]=message
        end
    end)
end
local function maintain(id,p)
    if stopped or loggedOut or shops[id]~=p then return end
    -- 削除済みのハンドルを保持すると、近距離でも二度と生成されなくなります。
    local ped=entities[id]
    if ped and (not DoesEntityExist(ped) or IsPedDeadOrDying(ped,true)) then clear(id) end
    local here=GetEntityCoords(PlayerPedId())
    local c=vec3(p.coords.x,p.coords.y,p.coords.z)
    local current=entities[id]
    if current then
        local expected=vec3(c.x,c.y,c.z+(p.coordinateMode=='origin' and 0.0 or 1.0))
        local heading=GetEntityHeading(current)
        local difference=math.abs((heading-p.heading+180)%360-180)
        if #(GetEntityCoords(current)-expected)>0.02 or difference>0.5 then anchor(current,p) end
        if not IsEntityVisible(current) then SetEntityVisible(current,true,false) end
    end
    local distance=#(here-c)
    if distance<streaming.spawnDistance and not approached[id] then
        approached[id]=true refreshRequested=true
    elseif distance>streaming.despawnDistance then approached[id]=nil end
    if distance<streaming.spawnDistance and not entities[id] and not zones[id] and not loading[id] then
        local options=targetOptions(p)
        if p.model then
            spawn(id,p,c,options)
        else
            zones[id]=exports.ox_target:addBoxZone({coords=vec3(c.x,c.y,c.z+0.5),size=vec3(2,2,3),drawSprite=true,options=options})
            spawnErrors[id]=nil
        end
    elseif distance>streaming.despawnDistance then clear(id) end
end
CreateThread(function()
    while not stopped do
        if not loggedOut then
        for id,p in pairs(shops) do
            local ok,err=pcall(maintain,id,p)
            if not ok then
                clear(id)
                local message=tostring(err)
                if spawnErrors[id]~=message then print(('[Omnite shops] NPC %s: %s'):format(id,message)) end
                spawnErrors[id]=message
            end
        end
        end
        Wait(1000)
    end
end)
CreateThread(function()
    Wait(1500)
    local nextRefresh,lastRefresh=0,-streaming.refreshCooldown
    while not stopped do
        local now=GetGameTimer()
        if not loggedOut and (now>=nextRefresh or (refreshRequested and now-lastRefresh>=streaming.refreshCooldown)) then
            refreshRequested=false lastRefresh=now
            local ok=refresh(true)
            nextRefresh=GetGameTimer()+(ok and streaming.refreshInterval or streaming.retryInterval)
        end
        Wait(1000)
    end
end)
AddEventHandler('QBCore:Client:OnPlayerLoaded',function() loggedOut=false refresh() end)
AddEventHandler('QBCore:Client:OnPlayerUnload',function()
    loggedOut=true stateVersion=stateVersion+1
    for id in pairs(shops) do clear(id) end
    shops={} isManager=false availableJobs={} approached={} refreshRequested=false
end)
AddEventHandler('QBCore:Client:OnJobUpdate',refresh)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    stopped=true for id in pairs(shops) do clear(id) end
end)
