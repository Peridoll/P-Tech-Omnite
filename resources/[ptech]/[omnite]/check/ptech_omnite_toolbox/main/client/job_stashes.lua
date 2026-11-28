local C=SeatingClient
local prefix='ptech_omnite_toolbox:jobstash:'
local points,zones={},{}
local stopped,loggedOut=false,false
local generation=0
local function notify(message) lib.notify({description=message}) end
local function call(action,...)
    local ok,result=pcall(lib.callback.await,prefix..action,false,...)
    if not ok then print('[Omnite job stash] '..tostring(result)) notify('ジョブ共有スタッシュの処理に接続できません。') return end
    if not result or not result.ok then notify(result and result.message or '処理に失敗しました。') return end
    return result
end
local function allowed(p)
    if not p or not p.enabled or stopped or loggedOut then return false end
    local data=exports.qbx_core:GetPlayerData() local job=data and data.job
    local grade=job and (type(job.grade)=='table' and job.grade.level or job.grade)
    return job and job.name==p.job and (tonumber(grade) or 0)>=p.minGrade or false
end
local function clear(id)
    local zone=zones[id] zones[id]=nil
    if zone then exports.ox_target:removeZone(zone) end
end
local function update(list)
    if stopped or loggedOut or type(list)~='table' then return end
    generation=generation+1
    for id,p in pairs(points) do
        local nextPoint=list[id]
        if not nextPoint or not nextPoint.enabled or p.name~=nextPoint.name or p.coords.x~=nextPoint.coords.x or p.coords.y~=nextPoint.coords.y or p.coords.z~=nextPoint.coords.z then clear(id) end
    end
    points=list
    for id,p in pairs(points) do
        if p.enabled and not zones[id] then
            local pointId=id
            zones[id]=exports.ox_target:addBoxZone({coords=vec3(p.coords.x,p.coords.y,p.coords.z),size=vec3(1.5,1.5,2.0),drawSprite=true,
                options={{name=prefix..id,label=p.name..'を開く',icon='fa-solid fa-box-archive',distance=Config.JobStashes.interactDistance,
                    canInteract=function() return allowed(points[pointId]) end,
                    onSelect=function()
                        local result=call('open',pointId)
                        if result then exports.ox_inventory:openInventory('stash',result.inventory) end
                    end,
                }},
            })
        end
    end
end
RegisterNetEvent(prefix..'state',update)
local function refresh(silent)
    local version=generation
    local ok,result=pcall(lib.callback.await,prefix..'list',false)
    if ok and result and result.ok and version==generation and not stopped and not loggedOut then update(result.points)
    elseif not silent and not loggedOut then notify('スタッシュ一覧を取得できませんでした。') end
end
local menu
local function edit(p,jobs)
    local options={} local seen={}
    for name,job in pairs(jobs) do options[#options+1]={value=name,label=(job.label or name)..' ('..name..')'} seen[name]=true end
    if p and not seen[p.job] then options[#options+1]={value=p.job,label=p.job..'（保存済み）'} end
    table.sort(options,function(a,b) return a.value<b.value end)
    local input=lib.inputDialog(p and 'ジョブ共有スタッシュを編集' or 'ジョブ共有スタッシュを設置',{
        {type='input',label='スタッシュ名',required=true,minLength=1,maxLength=64,default=p and p.name},
        {type='select',label='共有するJOB',required=true,searchable=true,options=options,default=p and p.job},
        {type='number',label='利用できる最低階級（0＝全階級）',required=true,min=0,max=100000,precision=0,default=p and p.minGrade or 0},
        {type='number',label='スロット数',required=true,min=1,max=Config.JobStashes.maxSlots,precision=0,default=p and p.slots or Config.JobStashes.slots},
        {type='number',label='重量上限（kg）',required=true,min=0.001,max=Config.JobStashes.weightLimit/1000,precision=3,default=(p and p.maxWeight or Config.JobStashes.maxWeight)/1000},
        {type='checkbox',label='有効化',checked=not p or p.enabled},
        {type='checkbox',label='現在地へ設置・移動する',checked=not p},
    })
    if not input then return end
    if call('save',{id=p and p.id,revision=p and p.revision,name=input[1],job=input[2],minGrade=input[3],slots=input[4],
        maxWeight=math.floor(input[5]*1000+0.5),enabled=input[6]==true,relocate=input[7]==true}) then notify('ジョブ共有スタッシュを保存しました。') end
    menu()
end
menu=function()
    if stopped or loggedOut then return end
    local result=call('list',true) if not result then return end
    if stopped or loggedOut then return end
    local options={{title='現在地にジョブ共有スタッシュを設置',icon='plus',onSelect=function() edit(nil,result.jobs or {}) end}}
    local entries={} for _,p in pairs(result.points) do entries[#entries+1]=p end
    table.sort(entries,function(a,b) return a.name<b.name end)
    for _,entry in ipairs(entries) do
        local p=entry
        options[#options+1]={title=p.name,description=('%s / 階級%d以上 / %d枠 / %.3fkg / %s'):format(p.job,p.minGrade,p.slots,p.maxWeight/1000,p.enabled and '有効' or '無効'),onSelect=function()
            lib.registerContext({id='omnite_job_stash_edit',title=p.name,menu='omnite_job_stashes',options={
                {title='JOB・容量・位置を編集',onSelect=function() edit(p,result.jobs or {}) end},
                {title='スタッシュを開く',description='指定JOB・最低階級を満たし、設置地点の近くにいる場合に開けます。',onSelect=function()
                    local opened=call('open',p.id)
                    if opened then exports.ox_inventory:openInventory('stash',opened.inventory) end
                end},
                {title='削除',icon='trash',onSelect=function()
                    if lib.alertDialog({header='共有スタッシュを削除',content='中身を空にしたスタッシュを削除しますか？',cancel=true})=='confirm' then call('delete',p.id,p.revision) end
                    menu()
                end},
            }}) lib.showContext('omnite_job_stash_edit')
        end}
    end
    lib.registerContext({id='omnite_job_stashes',title='ジョブ共有スタッシュ管理',options=options}) lib.showContext('omnite_job_stashes')
end
C.openJobStashes=menu
CreateThread(function()
    Wait(1500)
    while not stopped do
        if not loggedOut then refresh(true) end
        Wait(15000)
    end
end)
AddEventHandler('QBCore:Client:OnPlayerLoaded',function() loggedOut=false refresh(true) end)
AddEventHandler('QBCore:Client:OnJobUpdate',function()
    TriggerServerEvent(prefix..'checkAccess')
end)
AddEventHandler('QBCore:Client:OnPlayerUnload',function()
    loggedOut=true generation=generation+1
    for id in pairs(zones) do clear(id) end points={}
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    stopped=true generation=generation+1
    for id in pairs(zones) do clear(id) end points={}
end)
