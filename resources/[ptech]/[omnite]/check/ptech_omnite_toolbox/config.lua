Config = {}

-- 指定JOBのメンバーで中身を共有するスタッシュの設置設定。
Config.JobStashes = {
    maxTotal = 500, -- 設置数の上限
    slots = 100, -- 新規スタッシュの初期スロット数
    maxWeight = 500000, -- 初期重量上限（g、500kg）
    maxSlots = 500, -- 設定可能なスロット数の上限
    weightLimit = 100000000, -- 設定可能な重量上限（g）
    interactDistance = 2.5, -- 利用距離（m）
}

-- ショップ情報の再取得と、近距離のNPC読み込み。
Config.ShopStreaming = {
    spawnDistance = 80.0, -- この距離まで近づくと再取得・NPC生成（m）
    despawnDistance = 100.0, -- この距離より離れるとNPCを片付ける（m）
    refreshInterval = 15000, -- 一覧の取りこぼしを回復する定期同期（ms）
    refreshCooldown = 3000, -- 接近による再取得の最短間隔（ms）
    retryInterval = 5000, -- 一覧取得失敗時の再試行間隔（ms）
    modelTimeout = 5000, -- 各NPCモデルの読込待ち上限（ms）
}

-- 宝箱NPCごとの報酬セットと、キャラクターごとの受取記録をDBへ保存します。
Config.Treasure = {
    maxTotal = 500, -- 設置できるNPCの上限
    slots = 50, -- 報酬設定用スタッシュのスロット数
    maxWeight = 100000000, -- 設定用スタッシュの重量上限（g）
    interactDistance = 2.5, -- 話しかけられる距離（m）
    model = 's_m_m_highsec_01', -- 新規設置時のNPCモデル
}

-- 管理者が乗車中の車を、その場に複製する機能です。
Config.VehicleClone = {
    spacing = 2.0, -- 元車の大きさに追加する出現間隔（m）
    maxSpawnDistance = 50.0, -- 元車から複製先までの距離上限（m）
    cooldown = 5000, -- 同じ管理者が次に複製できるまでの間隔（ms）
    timeout = 20000, -- 複製先の読込・改造反映を待つ上限（ms）
}

-- 工具箱から配置する地図アイコン。登録後の設定はDBに保存します。
Config.MapBlips = {
    maxTotal = 500, -- 全インスタンスを合わせた設置上限
    defaultSprite = 1, -- 新規設置時のブリップアイコンID
    defaultColour = 0, -- 新規設置時の色ID
    defaultScale = 0.8, -- 新規設置時の表示倍率
    fixed = {}, -- 管理画面のConfig出力をここへ貼り付けできます。
}

-- ATMは既存の銀行リソースが反応するpropだけを設置します。
Config.ATMs = {
    models = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' },
    maxTotal = 500, -- 全インスタンスを合わせた設置上限
    streamDistance = 100.0, -- propを生成する距離（m）
    fixed = {}, -- 管理画面のConfig出力をここへ貼り付けできます。
}

Config.Circles = {
    interactDistance = 1.75,
    markerDistance = 30.0,
    maxTotal = 100,
    maxRadius = 5000.0,
    maxDelay = 3600,
    blipColour = 1,
    blipAlpha = 90,
    escapeDestination = { x = 215.76, y = -810.12, z = 30.73, heading = 157.0 },
}

Config.Teleporters = {
    interactDistance = 1.75,
    markerDistance = 25.0,
    maxTotal = 500,
    maxPerOwner = 100,
    cooldown = 2000,
    draftLifetime = 1800000,
}

Config.Placement = {
    item = 'pomnite_toolbox',
    command = 'omnite_seating',
    adminAce = 'omnite.seating.admin',
    maxDistance = 8.0,
    markerDistance = 30.0,
    markerInteractDistance = 1.75,
    maxPerOwner = 250,
    editByToolHolder = true,
    deleteByToolHolder = true,
    maxPerGroup = 32,
    groupDistance = 15.0,
    maxTotal = 5000,
    medicalResource = 'ptech_mediora_medical',
    emsJobs = { ambulance = true }, -- JOBのみ判定。グレード・出勤状態は問わない。
    bedAnimation = { dict = 'anim@gangops@morgue@table@', clip = 'body_search' },
}

Config.Seating = {
    targetLabel = '座る',
    targetDistance = 2.0,
    serverDistance = 3.0,
    standKey = 'X',
    standAnimation = { dict = 'switch@michael@sitting', clip = 'exit_forward', minimumDuration = 2200, maximumDuration = 6000, endPadding = 250 },
    exitSearch = { distances = { 0.85, 1.25, 1.75 }, probeTimeout = 150 },
    styleKey = 'G',
    defaultStyle = 'standard',
    styles = {
        { id = 'standard', label = '標準', scenario = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'upright', label = '背筋を伸ばす', scenario = 'PROP_HUMAN_SEAT_CHAIR_UPRIGHT', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'sit_chair', label = 'Sit Chair', dict = 'timetable@ron@ig_3_couch', clip = 'base', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'sit_chair_2', label = 'Sit Chair 2', dict = 'timetable@ron@ig_5_p3', clip = 'ig_5_p3_base', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'sit_side', label = 'Sit Chair 4 - Side', dict = 'timetable@ron@ron_ig_2_alt1', clip = 'ig_2_alt1_base', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'sit_crossed', label = 'Sit Chair Legs Crossed', dict = 'timetable@jimmy@mics3_ig_15@', clip = 'mics3_15_base_tracy', offset = vec3(1.0, 0.0, 0.0), headingOffset = 30.0 },
        { id = 'sit_lean_back', label = 'Sit Chair Lean Back', dict = 'timetable@maid@couch@', clip = 'base', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'sit_attentive', label = 'Sit Chair Attentive', dict = 'anim@scripted@freemode_npc@fix_astu_ig3_pooh_jimmy@jimmy@', clip = 'sit_base_jimmy', offset = vec3(1.0, 0.0, -1.0), headingOffset = 0.0 },
        { id = 'sit_lonely', label = 'Sit Chair Lonely', dict = 'anim@scripted@freemode_npc@fix_dre_studio_entourage@', clip = 'lonely_ballas', offset = vec3(0.0, 0.0, -1.0), headingOffset = 0.0 },
        { id = 'bar', label = 'カウンター座り', scenario = 'PROP_HUMAN_SEAT_BAR', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'lying', label = '仰向け', dict = Config.Placement.bedAnimation.dict, clip = Config.Placement.bedAnimation.clip, offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'sleep', label = '睡眠', dict = 'timetable@tracy@sleep@', clip = 'base', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'prone', label = 'うつ伏せ', dict = 'amb@world_human_sunbathe@male@front@base', clip = 'base', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
        { id = 'lie_relaxed', label = 'リラックスして横になる', dict = 'amb@world_human_sunbathe@male@back@base', clip = 'base', offset = vec3(0.0, 0.0, 0.0), headingOffset = 0.0 },
    },
    kindStyles = {
        chair = { 'standard', 'upright', 'sit_chair', 'sit_chair_2', 'sit_side', 'sit_crossed', 'sit_lean_back', 'sit_attentive', 'sit_lonely' },
        counter = { 'bar', 'standard', 'upright', 'sit_chair', 'sit_chair_2', 'sit_side', 'sit_crossed', 'sit_lean_back', 'sit_attentive', 'sit_lonely' },
        bed = { 'lying', 'sleep', 'prone', 'lie_relaxed' },
        patient_bed = { 'lying', 'sleep', 'prone', 'lie_relaxed' },
    },
}

-- 配置・利用・サーバー検証で共通の姿勢一覧を使用する。
OmniteSeating = {}
function OmniteSeating.stylesFor(kind, allowedIds)
    kind = kind or 'chair'
    local styles,allowed={},{}
    local function compatibleId(id)
        if (kind=='chair' or kind=='counter') and id=='armchair' then return 'standard' end
        if (kind=='bed' or kind=='patient_bed') and id=='standard' then return 'lying' end
        return id
    end
    if allowedIds then for _,id in ipairs(allowedIds) do allowed[compatibleId(id)]=true end end
    for _,id in ipairs(Config.Seating.kindStyles[kind] or {}) do
        if not allowedIds or allowed[id] then
            for _,style in ipairs(Config.Seating.styles) do if style.id==id then styles[#styles+1]=style break end end
        end
    end
    return styles
end
function OmniteSeating.styleFor(kind, id)
    if (kind=='chair' or kind=='counter') and id=='armchair' then id='standard' end
    if (kind=='bed' or kind=='patient_bed') and id=='standard' then id='lying' end
    for _,style in ipairs(OmniteSeating.stylesFor(kind)) do if style.id==id then return style end end
end

-- Enable only while setting up MLO seats. Both commands are ACE-restricted.
Config.SeatRecorder = {
    enabled = false,
    command = 'omnite_seatrecord',
    setupCommand = 'omnite_seatsetup',
    radius = 0.45,
    fineStep = 0.01,
    coarseStep = 0.05,
    headingStep = 1.0,
}

-- ACE-restricted tooling for inspecting configured seating in-game.
Config.SeatDebug = {
    command = 'omnite_seatdebug',
    ghostCommand = 'omnite_seatghost',
    markerDistance = 120.0,
    ghostDistance = 3.0,
    ghostScanDistance = 8.0,
}

-- Offsets are local to each object model. Tune them for chair models whose
-- default seat position or facing does not line up with the sitting scenario.
-- Add `styles = { 'standard', 'upright' }` to restrict a model when needed.
Config.ChairModels = {
    ['prop_chair_01a'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_01b'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_02'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_03'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_04a'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_04b'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_05'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_06'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_07'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_08'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_09'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_chair_10'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_off_chair_01'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_off_chair_03'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_off_chair_04'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_table_01_chr_a'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_table_02_chr'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
    ['prop_table_03b_chr'] = { offset = vec3(0.0, 0.0, 0.45), headingOffset = 180.0 },
}

-- Use fixed seats for MLO chairs that are not exposed as individual objects.
-- Each entry is one exclusive seat position.
Config.FixedSeats = {
    -- Example:
    -- { id = 'clinic_waiting_01', coords = vec3(307.25, -595.10, 43.28), heading = 70.0, styles = { 'standard', 'upright' } },
}
