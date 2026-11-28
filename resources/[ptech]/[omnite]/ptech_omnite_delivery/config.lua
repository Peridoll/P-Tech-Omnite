Config = {
    adminAce = 'omnite.delivery.admin',
    toolItem = 'pomnite_toolbox',
    boxItem = 'pomnite_delivery_box',
    interactDistance = 2.0,
    serverDistance = 3.0,
    missionSeconds = 1800,
    cooldownSeconds = 60,
    maxLocations = 300,
    maxPurchase = 100,
    -- 店員は勤務外でも利用可能。報酬は店長が店舗NPCから設定、獲得ポイントは管理者が配置時に設定します。
    -- 新規店舗の報酬初期値。既存店舗の店長設定は上書きしません。
    defaultReward = 400000,
    defaultPoints = 200,
    npcModel = 's_m_m_dockwork_01',
    gameplay = {
        -- 箱の受け取り・納品にかかる時間（ミリ秒）。演出をキャンセルすると受け渡しません。
        handoverDuration = 2500,
        -- 他リソースのTextUIを優先しながら、行き先・残り時間を表示します。
        showGuide = true,
        -- 対応する配達箱を持っているときの運搬表示。乗車・ダウン中は非表示です。
        carryBox = true,
        -- 運搬中に両手へ取り付ける箱のモデル名。
        boxModel = 'prop_cs_cardbox_01',
    },
    -- 既存の料理素材を使う場合は item を導入済みアイテムIDに変更してください。
    products = {
        { id = 'normal', label = '普通の飲食物資', item = 'pomnite_food_supply', cash = 7500, points = 3 },
        -- cashは従来の商品設定との互換用。現金ショップはツールボックスのショップ管理で設定します。
        { id = 'premium', label = '高級な飲食物資', item = 'pomnite_premium_supply', cash = 12500, points = 5 },
        { id = 'sweet', label = '甘味の飲食物資', item = 'pomnite_sweet_supply', cash = 12500, points = 5 },
        { id = 'tobacco_leaf', label = 'タバコの葉', item = 'pomnite_tobacco_leaf', cash = 7500, points = 3 },
        { id = 'tea_leaf', label = '紅茶の茶葉', item = 'pomnite_tea_leaf', cash = 7500, points = 3 },
    },
    -- DBから書き出した配置をここへ移せます。id は重複させないでください。
    -- kind: pickup（配達先NPC・箱受取）, shop（店舗NPC・受注/納品/ポイント交換）
    -- 配達先NPCのvisibility: 'always'（常時見せる）/ 'mission'（受注時のみ）。未指定は'mission'。
    locations = {},
}
