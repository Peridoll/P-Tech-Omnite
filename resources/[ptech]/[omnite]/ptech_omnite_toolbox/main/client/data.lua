local C=SeatingClient
local pending
local function request(kind,action,body)
    local prefix=kind=='seats' and 'ptech_omnite_seating:' or 'ptech_omnite_toolbox:teleport:'
    local ok,result=pcall(lib.callback.await,prefix..'csv',false,action,body)
    if not ok or not result then C.notify('サーバーに接続できません。') return end
    if not result.ok then C.notify(result.message or '処理に失敗しました。') return end
    return result
end
function C.openDataMenu(kind)
    local title=kind=='seats' and '椅子 & ベッド 管理' or 'テレポーター管理'
    lib.registerContext({id='omnite_data_menu',title=title,options={
        {title='管理モードに入る',onSelect=function()
            if kind=='seats' then C.openSeatManagement() else C.openTeleporters() end
        end},
        {title='CSV書き出し',onSelect=function()
            local result=request(kind,'export')
            if result then SendNUIMessage({action='csvExport',name='omnite_'..kind..'.csv',text=result.text}) C.notify('CSVを書き出しました: ptech_omnite_toolbox/'..result.filename) end
        end},
        {title='CSV読み込み',description='既存IDは更新、新規IDは追加します。',onSelect=function()
            pending=kind
            SendNUIMessage({action='csvImport',title=title})
            SetNuiFocus(true,true)
        end},
    }})
    lib.showContext('omnite_data_menu')
end
RegisterNUICallback('csvSubmit',function(data,cb)
    local kind=pending
    if not kind then cb({ok=false,message='画面を開き直してください。'}) return end
    if type(data.text)~='string' or #data.text>2000000 then cb({ok=false,message='CSVは2MB以下にしてください。'}) return end
    local result=request(kind,'import',data.text)
    if result then
        pending=nil SetNuiFocus(false,false)
        C.notify(('%d件を読み込みました。'):format(result.count))
    end
    cb(result or {ok=false,message='読み込みに失敗しました。通知内容を確認してください。'})
end)
RegisterNUICallback('csvCancel',function(_,cb) pending=nil SetNuiFocus(false,false) cb({ok=true}) end)
