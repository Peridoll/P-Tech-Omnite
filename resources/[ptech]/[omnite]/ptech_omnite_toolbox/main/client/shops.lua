local prefix='ptech_omnite_shops:'
local shops,entities,zones={},{},{}
local isManager=false
local stopped=false
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
    local options={}
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
    if #options==0 then options[1]={title='商品がありません。商品スタッシュへ入れてください。',disabled=true} end
    lib.registerContext({id='omnite_shop_products',title=p.name..' 商品詳細設定',options=options})
    lib.showContext('omnite_shop_products')
end
local function edit(p)
    local input=lib.inputDialog(p and 'ショップを編集' or 'ショップを設置',{
        {type='input',label='ショップ名',default=p and p.name,required=true,maxLength=64},
        {type='checkbox',label='NPCを配置する',checked=not p or p.model~=false},
        {type='input',label='NPCモデル名',default=p and p.model or 's_m_m_dockwork_01',maxLength=100},
        {type='checkbox',label='有限在庫モード',checked=not p or p.finite},
        {type='checkbox',label='購入JOB制限を設定する',checked=p and p.purchaseJob~=nil},
        {type='input',label='購入可能なJOB名',default=p and p.purchaseJob,maxLength=48},
        {type='input',label='在庫管理JOB名（空欄はadminのみ）',default=p and p.stockJob,maxLength=48},
        {type='checkbox',label='現在地・向きへ配置する',checked=not p},
    })
    if not input then return end
    if input[5] and (not input[6] or input[6]=='') then notify('購入JOB名を入力してください。') return end
    if input[2] and (not input[3] or not IsModelInCdimage(joaat(input[3])) or not IsModelAPed(joaat(input[3]))) then notify('有効なNPCモデル名を入力してください。') return end
    local c=GetEntityCoords(PlayerPedId())
    call('save',{id=p and p.id,revision=p and p.revision,name=input[1],model=input[2] and input[3] or false,
        finite=input[4]==true,purchaseJob=input[5] and input[6] or nil,stockJob=input[7]~='' and input[7] or nil,
        relocate=input[8]==true,coords={x=c.x,y=c.y,z=c.z},heading=GetEntityHeading(PlayerPedId())})
    managerMenu()
end
local function actionMenu(p)
    local options={{title='購入する',onSelect=function()
        local result=call('open',p.id)
        if result then exports.ox_inventory:openInventory('shop',{type=result.shop}) end
    end}}
    local data=exports.qbx_core:GetPlayerData()
    local job=data and data.job
    if isManager or (job and p.stockJob==job.name) then options[#options+1]={title='商品スタッシュ・在庫管理',onSelect=function() inventory(p.id,'stock') end} end
    if job and p.stockJob==job.name and job.isboss then options[#options+1]={title='売上金を回収',onSelect=function() inventory(p.id,'sales') end} end
    if isManager then options[#options+1]={title='商品詳細設定',onSelect=function() products(p) end} end
    lib.registerContext({id='omnite_shop_access',title=p.name,options=options}) lib.showContext('omnite_shop_access')
end
local function clear(id)
    if entities[id] then exports.ox_target:removeLocalEntity(entities[id]) DeleteEntity(entities[id]) entities[id]=nil end
    if zones[id] then exports.ox_target:removeZone(zones[id]) zones[id]=nil end
end
local function update(list)
    for id in pairs(shops) do if not list[id] or json.encode(shops[id])~=json.encode(list[id]) then clear(id) end end
    shops=list
end
RegisterNetEvent(prefix..'state',update)
local function refresh()
    local result=call('list') if result then isManager=result.manager update(result.shops) end
end
managerMenu=function()
    refresh()
    if not isManager then notify('管理者権限と工具箱が必要です。') return end
    local options={{title='新しいショップを設置',onSelect=function() edit() end}}
    for _,point in pairs(shops) do
        local p=point
        options[#options+1]={title=p.name,description=(p.finite and '有限在庫' or '無限在庫')..' / '..(p.purchaseJob or '購入制限なし'),onSelect=function()
            lib.registerContext({id='omnite_shop_edit',title=p.name,menu='omnite_shops_manager',options={
                {title='ショップ設定・NPCモデル・位置を編集',onSelect=function() edit(p) end},
                {title='商品登録・補充・レイアウト',onSelect=function() inventory(p.id,'stock') end},
                {title='商品詳細設定',onSelect=function() products(p) end},
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
CreateThread(function()
    Wait(1500) refresh()
    while not stopped do
        local here=GetEntityCoords(PlayerPedId())
        for id,p in pairs(shops) do
            local c=vec3(p.coords.x,p.coords.y,p.coords.z)
            if #(here-c)<80 and not entities[id] and not zones[id] then
                local option={name=prefix..id,label=p.name,icon='fa-solid fa-store',distance=2.5,onSelect=function() actionMenu(p) end}
                if p.model then
                    local ok,model=pcall(lib.requestModel,p.model,5000)
                    if ok and not stopped and shops[id]==p then
                        local ped=CreatePed(4,model,c.x,c.y,c.z,p.heading,false,false)
                        if ped~=0 then
                            entities[id]=ped SetEntityInvincible(ped,true) FreezeEntityPosition(ped,true) SetBlockingOfNonTemporaryEvents(ped,true)
                            exports.ox_target:addLocalEntity(ped,{option})
                        end
                        SetModelAsNoLongerNeeded(model)
                    end
                else zones[id]=exports.ox_target:addBoxZone({coords=vec3(c.x,c.y,c.z-0.5),size=vec3(2,2,3),drawSprite=true,options={option}}) end
            elseif #(here-c)>100 then clear(id) end
        end
        Wait(1000)
    end
end)
AddEventHandler('QBCore:Client:OnPlayerLoaded',refresh)
AddEventHandler('QBCore:Client:OnJobUpdate',refresh)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    stopped=true for id in pairs(shops) do clear(id) end
end)
