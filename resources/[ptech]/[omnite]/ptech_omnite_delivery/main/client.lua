local prefix = 'ptech_omnite_delivery:'
local locations, npcs, current = {}, {}, nil
local blip, busy, managing, stopped
local function notify(message, kind) lib.notify({description=message, type=kind or 'inform'}) end
local function call(action, ...)
    local ok, result = pcall(lib.callback.await, prefix..action, false, ...)
    if not ok or not result then notify('配達サーバーに接続できません。','error') return end
    if not result.ok then notify(result.message or '操作できません。','error') return end
    return result
end
local function route(m)
    current = m
    if blip then RemoveBlip(blip) blip = nil end
    local point = m and locations[m.picked and m.shop or m.pickup]
    if not point then return end
    blip = AddBlipForCoord(point.coords.x,point.coords.y,point.coords.z)
    SetBlipSprite(blip,478)
    SetBlipColour(blip,5)
    SetBlipRoute(blip,true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(m.picked and '箱の納品先' or '箱の集荷先')
    EndTextCommandSetBlipName(blip)
end
local function work(action,id)
    if busy then return end
    busy = true
    local result = call('work',action,id)
    busy = false
    if result then
        route(result.mission)
        if action == 'deliver' then notify(('納品完了：報酬 $%d ／ 店舗に %d 箱ポイント'):format(result.reward,result.points),'success')
        elseif action == 'pickup' then notify('箱を受け取りました。店舗へ納品してください。','success')
        elseif action == 'start' then notify('マップの箱マークに向かってください。')
        else notify('配達を取り消しました。') end
    else
        local state = call('state')
        if state then route(state.mission) end
    end
end
local function products(point)
    local options = {}
    for _, entry in ipairs(Config.products) do
        local product = entry
        local cash = point.kind == 'market'
        local price = cash and product.cash or product.points
        local configured = type(price) == 'number' and price > 0 and price % 1 == 0
        options[#options+1] = {title=product.label, disabled=not configured,
            description=not configured and '価格未設定' or (cash and ('$%d / 個'):format(price) or ('%d 箱ポイント / 個'):format(price)),
            onSelect=function()
                local input = lib.inputDialog(product.label, {{type='number',label='数量',default=1,min=1,max=Config.maxPurchase,required=true}})
                if not input or busy then return end
                local total = input[1]*(cash and product.cash or product.points)
                if lib.alertDialog({header='素材の購入',content=('%s × %d\n合計：%s'):format(product.label,input[1],cash and ('$'..total) or (total..' 箱ポイント')),cancel=true}) ~= 'confirm' then return end
                busy = true
                local result = call('buy',point.id,product.id,input[1])
                busy = false
                if result then notify(result.message,'success') end
            end}
    end
    lib.registerContext({id='omnite_delivery_products',title=point.label..'：素材購入',options=options})
    lib.showContext('omnite_delivery_products')
end
local function shopMenu(point)
    local result = call('shop',point.id)
    if not result then return end
    route(result.mission)
    local m = result.mission
    local options = {
        {title='配達を受注',description=('納品報酬 $%d ／ 店舗に %d 箱ポイント'):format(point.reward,point.points),disabled=m~=nil,onSelect=function() work('start',point.id) end},
        {title='箱を納品',disabled=not m or not m.picked or m.shop~=point.id,onSelect=function() work('deliver',point.id) end},
        {title='箱ポイントで素材を購入',description=('店舗共通残高：%d 箱ポイント'):format(result.points),onSelect=function() products(point) end},
    }
    if m then options[#options+1] = {title='配達を取り消す',onSelect=function()
        if lib.alertDialog({header='配達の取消',content='報酬は支払われません。受取済みの配達用の箱も回収します。',cancel=true}) == 'confirm' then work('cancel',point.id) end
    end} end
    lib.registerContext({id='omnite_delivery_shop',title=point.label,options=options})
    lib.showContext('omnite_delivery_shop')
end
local function removeNpc(id)
    local npc = npcs[id]
    if not npc then return end
    if npc.entity then
        exports.ox_target:removeLocalEntity(npc.entity)
        if DoesEntityExist(npc.entity) then DeleteEntity(npc.entity) end
    end
    npcs[id] = nil
end
local function createNpc(id,point)
    npcs[id] = {loading=true, point=point}
    local pending = npcs[id]
    local ok, model = pcall(lib.requestModel,Config.npcModel,5000)
    if not ok then if npcs[id]==pending then npcs[id]=nil end return end
    if stopped or npcs[id]~=pending or locations[id]~=point then SetModelAsNoLongerNeeded(model) return end
    local c = point.coords
    local ped = CreatePed(4,model,c.x,c.y,c.z,point.heading,false,false)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 then npcs[id]=nil return end
    pending.entity, pending.loading = ped, false
    SetEntityInvincible(ped,true)
    FreezeEntityPosition(ped,true)
    SetBlockingOfNonTemporaryEvents(ped,true)
    exports.ox_target:addLocalEntity(ped, {{
        name=prefix..id, label=point.kind=='pickup' and '配達用の箱を受け取る' or point.label,
        icon='fa-solid fa-box',distance=Config.interactDistance,
        canInteract=function()
            if busy or managing or IsPedDeadOrDying(PlayerPedId(),true) then return false end
            if point.kind=='pickup' then return current and not current.picked and current.pickup==id end
            local data = exports.qbx_core:GetPlayerData()
            local job = data and data.job
            return job and (not Config.requireDuty or job.onduty) and
                ((point.kind=='shop' and job.name==point.job) or (point.kind=='market' and job.isboss))
        end,
        onSelect=function()
            if point.kind=='pickup' then work('pickup',id)
            elseif point.kind=='shop' then shopMenu(point)
            else products(point) end
        end,
    }})
end
local function setLocations(list)
    for id,npc in pairs(npcs) do
        if not list[id] or json.encode(npc.point)~=json.encode(list[id]) then removeNpc(id) end
    end
    -- Preserve point references for model loads already in progress.
    for id,p in pairs(list) do if npcs[id] then list[id]=npcs[id].point end end
    locations = list
end
RegisterNetEvent(prefix..'locations',function(list) setLocations(list or {}) end)
CreateThread(function()
    while not stopped do
        local coords = GetEntityCoords(PlayerPedId())
        for id,point in pairs(locations) do
            local c = point.coords
            local distance = #(coords-vec3(c.x,c.y,c.z))
            if distance<80 and not npcs[id] then CreateThread(function() createNpc(id,point) end)
            elseif distance>100 and npcs[id] then removeNpc(id) end
        end
        if current and current.expires<=os.time() then route(nil) notify('配達の制限時間が終了しました。') end
        Wait(1000)
    end
end)
local function refresh()
    local result = call('state')
    if result then setLocations(result.locations) route(result.mission) end
end
CreateThread(function() Wait(1500) refresh() end)
AddEventHandler('QBCore:Client:OnPlayerLoaded',refresh)
AddEventHandler('QBCore:Client:OnJobUpdate',function() refresh() end)
AddEventHandler('QBCore:Client:OnPlayerUnload',function() route(nil) end)

local managerMenu
local function edit(point)
    local coords = GetEntityCoords(PlayerPedId())
    local heading = GetEntityHeading(PlayerPedId())
    local p = point or {coords={x=coords.x,y=coords.y,z=coords.z},heading=heading,kind='shop',reward=Config.defaultReward,points=Config.defaultPoints}
    local input = lib.inputDialog('配達NPCの登録・編集', {
        {type='input',label='地点ID（半角英数字・_・-）',default=p.id,required=true,max=48,disabled=point~=nil},
        {type='input',label='表示名',default=p.label,required=true,max=64},
        {type='select',label='種類',default=p.kind,required=true,options={{value='shop',label='店舗：受注・納品・箱ポイント交換'},{value='pickup',label='集荷NPC'},{value='market',label='スーパー：店長の現金購入'}}},
        {type='input',label='店舗のジョブ名（店舗のみ必須）',default=p.job},
        {type='number',label='納品1回の現金報酬（店舗のみ）',default=p.reward or Config.defaultReward,min=0,max=10000000,required=true},
        {type='number',label='納品1回の箱ポイント（店舗のみ）',default=p.points or Config.defaultPoints,min=1,max=10000,required=true},
        {type='checkbox',label='現在地・現在の向きに配置する',checked=not point},
    })
    if not input then return end
    if input[7] then coords=GetEntityCoords(PlayerPedId()) heading=GetEntityHeading(PlayerPedId())
    else coords=p.coords heading=p.heading end
    local result = call('manage','save',{id=point and point.id or input[1],label=input[2],kind=input[3],job=input[4],reward=input[5],points=input[6],
        coords={x=coords.x,y=coords.y,z=coords.z},heading=heading})
    if result then notify('NPCを保存しました。','success') end
    managerMenu()
end
local function exportConfig(list)
    local lines = {'Config.locations = {'}
    for _,p in ipairs(list) do
        lines[#lines+1] = ('    { id=%q, label=%q, kind=%q, bucket=%d, coords={x=%.4f,y=%.4f,z=%.4f}, heading=%.2f%s },')
            :format(p.id,p.label,p.kind,p.bucket,p.coords.x,p.coords.y,p.coords.z,p.heading,
                p.kind=='shop' and (', job=%q, reward=%d, points=%d'):format(p.job,p.reward,p.points) or '')
    end
    lines[#lines+1] = '}'
    lib.setClipboard(table.concat(lines,'\n'))
    notify('配置をConfig形式でコピーしました。')
end
managerMenu = function()
    local result = call('state')
    if not result or not result.manager then notify('管理者権限と工具箱が必要です。','error') return end
    setLocations(result.locations)
    local options = {{title='現在地にNPCを新規登録',onSelect=function() edit() end},
        {title='配置をConfig形式で書き出す',onSelect=function()
            local data = call('manage','export')
            if data then exportConfig(data.locations) end
        end}}
    for _,point in pairs(locations) do
        local p = point
        options[#options+1] = {title=p.label,description=p.kind..' / '..p.id..(p.job and (' / '..p.job) or ''),onSelect=function()
            lib.registerContext({id='omnite_delivery_edit',title=p.label,menu='omnite_delivery_manager',options={
                {title='設定を編集・現在地へ移設',onSelect=function() edit(p) end},
                {title='削除',onSelect=function()
                    if lib.alertDialog({header='NPCの削除',content=p.label..' を削除しますか？',cancel=true})=='confirm' then
                        local deleted = call('manage','delete',p.id)
                        if deleted then notify('NPCを削除しました。') end
                    end
                    managerMenu()
                end},
            }}) lib.showContext('omnite_delivery_edit')
        end}
    end
    lib.registerContext({id='omnite_delivery_manager',title='配達・素材仕入れの管理',options=options})
    lib.showContext('omnite_delivery_manager')
end
exports('openManager',function()
    if managing or busy then return end
    managing = true
    local ok,err = pcall(managerMenu)
    managing = false
    if not ok then print('[Omnite delivery] '..tostring(err)) notify('配達の管理画面を開けませんでした。','error') end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    stopped = true
    route(nil)
    for id in pairs(npcs) do removeNpc(id) end
    local context = lib.getOpenContextMenu()
    if context and context:match('^omnite_delivery_') then lib.hideContext(false) end
end)
