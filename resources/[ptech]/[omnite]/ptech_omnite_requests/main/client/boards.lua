local prefix='ptech_omnite_requests:boards:'
local zones={}
local function notify(message) lib.notify({description=message}) end
local function call(action,...)
    local result=lib.callback.await(prefix..action,false,...)
    if not result or not result.ok then notify(result and result.message or '処理に失敗しました。') return end
    return result
end
local function sync(boards)
    for _,zone in ipairs(zones) do exports.ox_target:removeZone(zone) end
    zones={}
    Config.Boards=boards or {}
    for _,p in ipairs(Config.Boards) do
        local board=p
        zones[#zones+1]=exports.ox_target:addBoxZone({
            coords=vec3(board.coords.x,board.coords.y,board.coords.z),
            size=vec3(board.size.x,board.size.y,board.size.z),rotation=board.rotation or 0,
            options={{name='omnite_request_'..board.id,icon='fa-solid fa-clipboard-list',label=board.label,
                distance=Config.InteractionDistance,onSelect=function() showBoard(board.id) end}},
        })
    end
end
RegisterNetEvent(prefix..'state',sync)
local actions={'view','post','accept','deliver','manage'}
local labels={view='閲覧',post='投稿',accept='受注',deliver='納品',manage='依頼管理'}
local menu
local function edit(board)
    local values=lib.inputDialog('依頼ボードの設置・編集',{
        {type='input',label='ボード名',required=true,max=64,default=board and board.label},
        {type='select',label='種類',required=true,default=board and board.type or 'general',options={{label='一般',value='general'},{label='ジョブ',value='job'}}},
        {type='checkbox',label='現在地・向きへ設置する',checked=not board},
    })
    if not values then return end
    local permissions={}
    for _,action in ipairs(actions) do
        local existing=board and board.permissions and board.permissions[action] or {public=action=='view' or action=='accept' or action=='deliver'}
        local jobs={} for name,grade in pairs(existing.jobs or {}) do jobs[#jobs+1]=name..':'..tostring(type(grade)=='table' and grade.minGrade or grade) end
        local input=lib.inputDialog(labels[action]..'できる人',{
            {type='checkbox',label='誰でも許可',checked=existing.public==true},
            {type='input',label='JOBと最低階級（例 ambulance:0,police:2）',default=table.concat(jobs,','),max=1000},
            {type='input',label='個別指定する市民ID（カンマ区切り）',default=table.concat(existing.citizenids or {},','),max=6500},
        })
        if not input then return end
        local rule={public=input[1]==true,jobs={},citizenids={},gangs=existing.gangs}
        for token in (input[2] or ''):gmatch('[^,]+') do
            local name,grade=token:match('^%s*([%w_-]+):(%d+)%s*$')
            if not name then notify('JOBは job:階級 の形式で指定してください。') return end
            local old=existing.jobs and existing.jobs[name]
            rule.jobs[name]=type(old)=='table' and {minGrade=tonumber(grade),onDuty=old.onDuty} or tonumber(grade)
        end
        for id in (input[3] or ''):gmatch('[^,]+') do rule.citizenids[#rule.citizenids+1]=id:match('^%s*(.-)%s*$') end
        permissions[action]=rule
    end
    call('save',{id=board and board.id,revision=board and board.revision,label=values[1],type=values[2],relocate=values[3]==true,permissions=permissions})
    menu()
end
menu=function()
    local result=call('list',true) if not result then return end
    local options={{title='現在地に依頼ボードを設置',icon='plus',onSelect=function() edit() end},
        {title='Config形式で出力',icon='copy',onSelect=function()
            local text='Config.Boards = '..PTechRequests.ToLua(result.boards)
            -- 工具箱のコピー画面はこのリソースから利用できないためox_libでコピーします。
            local ok=pcall(lib.setClipboard,text)
            if ok then notify('Config.Boardsの設定をコピーしました。')
            else lib.inputDialog('Config出力',{{type='textarea',label='コピーして設定へ貼り付け',default=text,min=8,max=20}}) end
        end}}
    for _,p in ipairs(result.boards) do
        local board=p
        options[#options+1]={title=board.label,description=board.id,onSelect=function()
            lib.registerContext({id='omnite_request_board_edit',title=board.label,menu='omnite_request_boards',options={
                {title='位置・権限を編集',onSelect=function() edit(board) end},
                {title='ボードを削除',description='投稿済みの依頼履歴は保持します。',icon='trash',onSelect=function()
                    if lib.alertDialog({header='ボードを削除',content=board.label..'を削除しますか？',cancel=true})=='confirm' then call('delete',board.id,board.revision) end
                    menu()
                end},
            }}) lib.showContext('omnite_request_board_edit')
        end}
    end
    lib.registerContext({id='omnite_request_boards',title='依頼ボード管理',options=options}) lib.showContext('omnite_request_boards')
end
exports('openManager',menu)
CreateThread(function()
    -- DB初期化中は後続のstate通知で登録します。
    local result=lib.callback.await(prefix..'list',false)
    if result and result.ok then sync(result.boards) end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() then for _,zone in ipairs(zones) do exports.ox_target:removeZone(zone) end end
end)
