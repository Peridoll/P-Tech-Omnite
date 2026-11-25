DeliveryGameplay = {}
local G = DeliveryGameplay
local active, points, box, carrier, guide, handing, stopped
local generation = 0
local dict, clip = 'anim@heists@box_carry@', 'idle'
local function clearBox()
    if box and DoesEntityExist(box) then DeleteEntity(box) end
    box = nil
    if carrier and DoesEntityExist(carrier) and IsEntityPlayingAnim(carrier,dict,clip,3) then
        StopAnimTask(carrier,dict,clip,2.0)
    end
    carrier = nil
end
local function hideGuide()
    local _, text = lib.isTextUIOpen()
    if guide and text == guide then lib.hideTextUI() end
    guide = nil
end
function G.update(m, locations)
    if not active or not m or active.token ~= m.token or active.picked ~= m.picked then
        generation = generation+1
        clearBox()
    end
    active, points = m, locations or {}
    if not active then hideGuide() end
end
local function hasBox()
    for _, slot in pairs(exports.ox_inventory:Search('slots',Config.boxItem) or {}) do
        if slot.count > 0 and slot.metadata and slot.metadata.delivery == active.token then return true end
    end
    return false
end
local function canCarry(ped)
    return not stopped and active and active.picked and active.expires > os.time() and not handing
        and not IsPedInAnyVehicle(ped,false) and not IsPedDeadOrDying(ped,true)
        and not IsPedRagdoll(ped) and not IsPedCuffed(ped) and hasBox()
end
local function carry()
    local ped = PlayerPedId()
    if not Config.gameplay.carryBox or not canCarry(ped) then clearBox() return end
    if carrier ~= ped or (box and not DoesEntityExist(box)) then clearBox() end
    if not box then
        local expected = generation
        local ok, model = pcall(lib.requestModel,Config.gameplay.boxModel,3000)
        if not ok then return end
        local loaded = pcall(lib.requestAnimDict,dict,3000)
        if not loaded or expected ~= generation or not canCarry(ped) then SetModelAsNoLongerNeeded(model) return end
        local c = GetEntityCoords(ped)
        box = CreateObject(model,c.x,c.y,c.z,true,false,false)
        SetModelAsNoLongerNeeded(model)
        if not box or box == 0 then box = nil return end
        carrier = ped
        SetEntityCollision(box,false,false)
        AttachEntityToEntity(box,ped,GetPedBoneIndex(ped,28422),0,0,0,0,0,0,true,true,false,true,1,true)
    end
    if not IsEntityPlayingAnim(ped,dict,clip,3) then
        TaskPlayAnim(ped,dict,clip,4.0,-4.0,-1,49,0,false,false,false)
    end
end
local function showGuide()
    if not active or active.expires <= os.time() or not Config.gameplay.showGuide or handing then hideGuide() return end
    local opened, text = lib.isTextUIOpen()
    if opened and text ~= guide then return end
    local target = points[active.picked and active.shop or active.pickup]
    if not target then hideGuide() return end
    local remaining = math.max(0,active.expires-os.time())
    local step = active.picked and '2/2 店舗NPCへ箱を納品' or '1/2 箱マークのNPCで箱を受取'
    local message = ('配達中 | %s\n行き先：%s | 残り %02d:%02d\n報酬 $%d / 店舗 +%d 箱ポイント')
        :format(step,target.label,remaining//60,remaining%60,active.reward or 0,active.points or 0)
    if message ~= guide or not opened then
        lib.showTextUI(message,{position='top-center',icon='box'})
        guide = message
    end
end
function G.handover(action)
    if handing or stopped or IsPedInAnyVehicle(PlayerPedId(),false) then
        lib.notify({description='車を降りて箱を受け渡してください。',type='error'})
        return false
    end
    local expected = generation
    handing = true
    clearBox()
    hideGuide()
    local ok, completed = pcall(lib.progressCircle,{
        duration=Config.gameplay.handoverDuration,
        label=action == 'pickup' and '箱を受け取っています' or '箱を納品しています',
        position='bottom',useWhileDead=false,canCancel=true,
        disable={move=true,car=true,combat=true},
        anim={dict='mp_common',clip='givetake1_a'},
    })
    handing = false
    if not ok then print('[Omnite delivery] Handover: '..tostring(completed)) end
    return ok and completed == true and expected == generation and not stopped
end
function G.stop()
    stopped = true
    generation = generation+1
    active = nil
    if handing and lib.progressActive() then lib.cancelProgress() end
    clearBox()
    hideGuide()
end
CreateThread(function()
    while not stopped do
        carry()
        showGuide()
        Wait(500)
    end
end)
