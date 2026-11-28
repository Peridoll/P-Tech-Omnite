local prefix = 'ptech_omnite_delivery:'
local locations, npcs, current = {}, {}, nil
local blip, busy, managing, stopped
local spawnErrors={}
local kindNames = {pickup='配達先NPC',shop='店舗NPC'}
local removeNpc
local function shouldShowNpc(id,point)
    return point.kind=='shop' or (point.kind=='pickup' and (point.visibility=='always'
        or (current and not current.picked and current.pickup==id and current.expires>GetCloudTimeAsInt())))
end
local function notify(message, kind) lib.notify({description=message, type=kind or 'inform'}) end
local function call(action, ...)
    local ok, result = pcall(lib.callback.await, prefix..action, false, ...)
    if not ok or not result then notify('配達サーバーに接続できません。','error') return end
    if not result.ok then notify(result.message or '操作できません。','error') return end
    return result
end
local function route(m)
    current = m
    for id,npc in pairs(npcs) do
        if not shouldShowNpc(id,npc.point) then removeNpc(id) end
    end
    DeliveryGameplay.update(m,locations)
    if blip then RemoveBlip(blip) blip = nil end
    local point = m and locations[m.picked and m.shop or m.pickup]
    if not point then return end
    blip = AddBlipForCoord(point.coords.x,point.coords.y,point.coords.z)
    SetBlipSprite(blip,478)
    SetBlipColour(blip,5)
    SetBlipRoute(blip,true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(m.picked and '店舗NPC：箱の納品先' or '配達先NPC：箱の受取')
    EndTextCommandSetBlipName(blip)
end
local function work(action,id)
    if busy then return end
    busy = true
    if (action == 'pickup' or action == 'deliver') and not DeliveryGameplay.handover(action) then
        busy = false
        return
    end
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
    local result=call('shop',point.id)
    if not result then return end
    local options = {}
    for _, entry in ipairs(result.products or Config.products) do
        local product = entry
        local price = product.points
        local configured = type(price) == 'number' and price > 0 and price % 1 == 0
        options[#options+1] = {title=product.label, disabled=not configured,
            description=not configured and '必要ポイント未設定' or ('%d 箱ポイント / 個'):format(price),
            onSelect=function()
                local input = lib.inputDialog(product.label, {{type='number',label='数量',default=1,min=1,max=Config.maxPurchase,required=true}})
                if not input or busy then return end
                local total = input[1]*price
                if lib.alertDialog({header='素材の購入',content=('%s × %d\n合計：%d 箱ポイント'):format(product.label,input[1],total),cancel=true}) ~= 'confirm' then return end
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
    point.reward=result.reward or point.reward
    local options = {
        {title='配達を受注',description=('納品報酬 $%d ／ 店舗に %d 箱ポイント'):format(point.reward,point.points),disabled=m~=nil,onSelect=function() work('start',point.id) end},
        {title='箱を納品',disabled=not m or not m.picked or m.shop~=point.id,onSelect=function() work('deliver',point.id) end},
        {title='箱ポイントで素材を購入',description=('店舗共通残高：%d 箱ポイント'):format(result.points),onSelect=function() products(point) end},
    }
    if result.boss then options[#options+1]={title='配達員の報酬設定（店長）',description=('現在の1回分：$%d ／ 次の受注から適用'):format(point.reward),onSelect=function()
        local input=lib.inputDialog('配達員への報酬（店長設定）',{
            {type='number',label='納品1回の現金報酬',default=point.reward,min=0,max=100000000,precision=0,required=true},
        })
        if input then
            local saved=call('vault',point.id,'reward',input[1])
            if saved then notify('配達報酬を変更しました。次の受注から適用されます。','success') end
        end
        shopMenu(point)
    end} end
    if result.boss then options[#options+1]={title='店舗金庫（店長）',description=('金庫残高 $%d'):format(result.vault or 0),onSelect=function()
        local input=lib.inputDialog('店舗金庫（店長専用）',{
            {type='select',label='操作',required=true,options={{value='deposit',label='現金を入金'},{value='withdraw',label='現金を出金'}}},
            {type='number',label='金額',min=0,max=100000000,precision=0,required=true},
        })
        if input then call('vault',point.id,input[1],input[2]) end
        shopMenu(point)
    end} end
    if m then options[#options+1] = {title='配達の行き先を表示',icon='map-location-dot',onSelect=function() route(m) end} end
    if m then options[#options+1] = {title='配達を取り消す',onSelect=function()
        if lib.alertDialog({header='配達の取消',content='報酬は支払われません。受取済みの配達用の箱も回収します。',cancel=true}) == 'confirm' then work('cancel',point.id) end
    end} end
    lib.registerContext({id='omnite_delivery_shop',title=point.label,options=options})
    lib.showContext('omnite_delivery_shop')
end
removeNpc = function(id)
    local npc = npcs[id]
    if not npc then return end
    if npc.entity then
        pcall(function() exports.ox_target:removeLocalEntity(npc.entity) end)
        if DoesEntityExist(npc.entity) then DeleteEntity(npc.entity) end
    end
    npcs[id] = nil
end
local function createNpc(id,point,pending)
    if stopped or npcs[id]~=pending or locations[id]~=point then return end
    if not shouldShowNpc(id,point) then npcs[id]=nil return end
    local ok, model = pcall(lib.requestModel,point.model or Config.npcModel,5000)
    if not ok then error('NPC model load failed: '..tostring(model)) end
    if stopped or npcs[id]~=pending or locations[id]~=point then SetModelAsNoLongerNeeded(model) return end
    if not shouldShowNpc(id,point) then npcs[id]=nil SetModelAsNoLongerNeeded(model) return end
    local c = point.coords
    -- 保存値はプレイヤーの中心座標。モデルの高さを引くと床に埋まるため減算しない。
    local ped = CreatePed(4,model,c.x,c.y,c.z,point.heading,false,true)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 or not DoesEntityExist(ped) then error('CreatePed returned no entity') end
    pending.entity, pending.loading = ped, false
    SetEntityAsMissionEntity(ped,true,true)
    -- 生成時の補正に依存せず、保存した中心座標へ直接合わせてから固定する。
    SetEntityCoordsNoOffset(ped,c.x,c.y,c.z,false,false,false)
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
            return job and point.kind=='shop' and job.name==point.job
        end,
        onSelect=function()
            if point.kind=='pickup' then work('pickup',id)
            elseif point.kind=='shop' then shopMenu(point) end
        end,
    }})
    spawnErrors[id]=nil
end
local function spawnNpc(id,point)
    local pending={loading=true,point=point}
    npcs[id]=pending
    CreateThread(function()
        local ok,err=xpcall(function() createNpc(id,point,pending) end,debug.traceback)
        if not ok then
            if npcs[id]==pending then removeNpc(id) end
            if spawnErrors[id]~=tostring(err) then
                spawnErrors[id]=tostring(err)
                print(('[Omnite delivery] NPC spawn failed: %s (%s), model=%s, coords=%.2f,%.2f,%.2f\n%s')
                    :format(point.label,id,point.model or Config.npcModel,point.coords.x,point.coords.y,point.coords.z,tostring(err)))
            end
        end
    end)
end
local function setLocations(list)
    for id,npc in pairs(npcs) do
        if not list[id] or json.encode(npc.point)~=json.encode(list[id]) then removeNpc(id) end
    end
    -- Preserve point references for model loads already in progress.
    for id,p in pairs(list) do if npcs[id] then list[id]=npcs[id].point end end
    locations = list
end
RegisterNetEvent(prefix..'locations',function(list)
    setLocations(list or {})
    DeliveryGameplay.update(current,locations)
end)
RegisterNetEvent(prefix..'missionEnded',function(token,reason)
    if not current or current.token ~= token then return end
    route(nil)
    notify(reason or '配達を終了しました。')
end)
CreateThread(function()
    while not stopped do
        local coords = GetEntityCoords(PlayerPedId())
        for id,point in pairs(locations) do
            local c = point.coords
            local distance = #(coords-vec3(c.x,c.y,c.z))
            local npc=npcs[id]
            if npc and npc.entity and not DoesEntityExist(npc.entity) then removeNpc(id) end
            if not shouldShowNpc(id,point) then
                if npcs[id] then removeNpc(id) end
            elseif distance<80 and not npcs[id] then spawnNpc(id,point)
            elseif distance>100 and npcs[id] then removeNpc(id) end
        end
        if current and current.expires<=GetCloudTimeAsInt() then route(nil) notify('配達の制限時間が終了しました。') end
        Wait(1000)
    end
end)
local function refresh()
    local result = call('state')
    if result then setLocations(result.locations) route(result.mission) end
end
CreateThread(function() Wait(1500) refresh() end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded',refresh)
RegisterNetEvent('QBCore:Client:OnJobUpdate',function() refresh() end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload',function() route(nil) end)

local managerMenu, productMenu
local function editProduct(product,revision,items)
    local fields={
        {type='input',label='商品ID（半角英数字・_・-）',default=product and product.id,required=true,maxLength=48,disabled=product~=nil},
        {type='select',label='販売アイテム',options=items,default=product and product.item,searchable=true,required=true},
        {type='input',label='商品名',default=product and product.label,required=true,maxLength=64},
        {type='number',label='必要な箱ポイント',required=true,default=product and (product.points or 0)>0 and product.points or nil,min=1,max=100000,precision=0},
    }
    local input=lib.inputDialog(product and '商品を編集' or '商品を追加',fields)
    if input then
        local result=call('manage','saveProduct',{revision=revision,product={id=product and product.id or input[1],
            item=input[2],label=input[3],points=input[4]}})
        if result then notify('商品設定を保存し、ショップへ反映しました。','success') end
    end
    productMenu()
end
productMenu=function()
    local result=call('manage','products')
    if not result then return end
    local options={{title='商品を追加',icon='plus',onSelect=function() editProduct(nil,result.revision,result.items) end}}
    for _,entry in ipairs(result.products) do
        local product=entry
        options[#options+1]={title=product.label,description=product.item..' / '..
            (product.points and (product.points..' 箱ポイント') or 'ポイント交換なし'),onSelect=function()
            lib.registerContext({id='omnite_delivery_product_edit',title=product.label,menu='omnite_delivery_product_manager',options={
                {title='アイテム・価格を編集',onSelect=function() editProduct(product,result.revision,result.items) end},
                {title='商品を削除',onSelect=function()
                    if lib.alertDialog({header='商品を削除',content=product.label..' を販売・交換一覧から削除しますか？',cancel=true})=='confirm' then
                        local deleted=call('manage','deleteProduct',{id=product.id,revision=result.revision})
                        if deleted then notify('商品を削除しました。','success') end
                    end
                    productMenu()
                end},
            }})
            lib.showContext('omnite_delivery_product_edit')
        end}
    end
    lib.registerContext({id='omnite_delivery_product_manager',title='素材の交換ポイント設定',menu='omnite_delivery_manager',options=options})
    lib.showContext('omnite_delivery_product_manager')
end
local function edit(point,kind)
    local coords = GetEntityCoords(PlayerPedId())
    local heading = GetEntityHeading(PlayerPedId())
    local p = point or {coords={x=coords.x,y=coords.y,z=coords.z},heading=heading,kind=kind or 'shop',reward=Config.defaultReward,points=Config.defaultPoints}
    local fields = {
        {type='input',label='地点ID（半角英数字・_・-）',default=p.id,required=true,maxLength=48,disabled=point~=nil},
        {type='input',label='表示名',default=p.label or kindNames[p.kind],required=true,maxLength=64},
        {type='checkbox',label='現在地・現在の向きに配置する',checked=not point},
    }
    if p.kind == 'shop' then
        fields[#fields+1] = {type='input',label='店舗のジョブ名',default=p.job,required=true,maxLength=48}
        fields[#fields+1] = {type='number',label='納品1回の箱ポイント',default=p.points,min=1,max=10000,required=true}
    else
        fields[#fields+1] = {type='select',label='NPCの表示',default=p.visibility or 'mission',required=true,options={
            {value='always',label='常時見せる'},
            {value='mission',label='受注時のみ見せる'},
        }}
    end
    fields[#fields+1]={type='input',label='NPCモデル名',default=p.model or Config.npcModel,required=true,maxLength=100}
    local input = lib.inputDialog(kindNames[p.kind]..'の配置・編集', fields)
    if not input then return end
    local model=input[#fields]
    if not IsModelInCdimage(joaat(model)) or not IsModelAPed(joaat(model)) then notify('有効なNPCモデルを指定してください。') return end
    if input[3] then coords=GetEntityCoords(PlayerPedId()) heading=GetEntityHeading(PlayerPedId())
    else coords=p.coords heading=p.heading end
    local result = call('manage','save',{id=point and point.id or input[1],label=input[2],kind=p.kind,
        job=p.kind=='shop' and input[4] or nil,points=p.kind=='shop' and input[5] or nil,
        coords={x=coords.x,y=coords.y,z=coords.z},heading=heading,model=model,
        visibility=p.kind=='pickup' and input[4] or nil})
    if result then notify('NPCを保存しました。','success') end
    managerMenu()
end
local function exportConfig(list,catalog)
    local lines = {'Config.locations = {'}
    for _,p in ipairs(list) do
        lines[#lines+1] = ('    { id=%q, label=%q, kind=%q, bucket=%d, coords={x=%.4f,y=%.4f,z=%.4f}, heading=%.2f%s%s%s },')
            :format(p.id,p.label,p.kind,p.bucket,p.coords.x,p.coords.y,p.coords.z,p.heading,
                p.kind=='shop' and (', job=%q, reward=%d, points=%d'):format(p.job,p.reward,p.points) or '',
                p.model and (', model=%q'):format(p.model) or '',
                p.kind=='pickup' and (', visibility=%q'):format(p.visibility or 'mission') or '')
    end
    lines[#lines+1] = '}'
    if catalog then
        lines[#lines+1]='Config.products = {'
        for _,product in ipairs(catalog) do
            lines[#lines+1]=('    { id=%q, label=%q, item=%q, cash=%s, points=%s },')
                :format(product.id,product.label,product.item,tostring(product.cash),tostring(product.points))
        end
        lines[#lines+1]='}'
    end
    lib.setClipboard(table.concat(lines,'\n'))
    notify('配置をConfig形式でコピーしました。')
end
local function reviewMenu()
    local result=call('reviews') if not result then return end
    local options={}
    for _,kind in ipairs({'runs','transfers'}) do
        for _,entry in ipairs(result[kind]) do
            local row=entry
            options[#options+1]={title=(kind=='runs' and '配達報酬' or '金庫入出金')..' / '..row.token,description=row.owner..' / '..tostring(row.reward or row.amount),onSelect=function()
                local decision=lib.inputDialog('障害発生前の現金移動を確認してください',{{type='select',label='確認結果',required=true,options=kind=='runs' and {
                    {value='paid',label='報酬支給済み：ポイント確定'},{value='refund',label='未支給：金庫に返金'}
                } or {{value='moved',label='現金移動済み'},{value='unmoved',label='現金未移動'}}}})
                if decision and lib.alertDialog({header='精算確認',content='ログと実際の残高を確認済みですか？この判断を記録します。',cancel=true})=='confirm' then
                    call('reviews',kind=='runs' and 'run' or 'transfer',row.token,decision[1])
                end
                reviewMenu()
            end}
        end
    end
    if #options==0 then options[1]={title='確認待ちの精算はありません',disabled=true} end
    lib.registerContext({id='omnite_delivery_reviews',title='障害時の精算確認',options=options}) lib.showContext('omnite_delivery_reviews')
end
managerMenu = function()
    local result = call('state')
    if not result or not result.manager then notify('管理者権限と工具箱が必要です。','error') return end
    setLocations(result.locations)
    local options = {
        {title='配達先NPCの配置',icon='box',description='受注時にランダムで選ばれる箱の受取先',onSelect=function() edit(nil,'pickup') end},
        {title='店舗NPCの配置',icon='store',description='店員の配達受注・納品・箱ポイント交換',onSelect=function() edit(nil,'shop') end},
        {title='素材の交換ポイント設定',icon='tags',description='配達ポイントで交換する素材と必要ポイント',onSelect=productMenu},
        {title='障害時の精算確認',icon='receipt',onSelect=reviewMenu},
        {title='配置をConfig形式で書き出す',onSelect=function()
            local data = call('manage','export')
            if data then exportConfig(data.locations,data.products) end
        end}}
    for _,point in pairs(locations) do
        local p = point
        options[#options+1] = {title=p.label,description=kindNames[p.kind]..' / '..p.id..(p.job and (' / '..p.job) or ''),onSelect=function()
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
    lib.registerContext({id='omnite_delivery_manager',title='デリバリー管理',options=options})
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
    DeliveryGameplay.stop()
    route(nil)
    for id in pairs(npcs) do removeNpc(id) end
    local context = lib.getOpenContextMenu()
    if context and context:match('^omnite_delivery_') then lib.hideContext(false) end
end)
