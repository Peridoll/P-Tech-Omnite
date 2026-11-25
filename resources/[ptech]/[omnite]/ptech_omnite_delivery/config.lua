Config = {
    adminAce = 'omnite.delivery.admin',
    toolItem = 'pomnite_toolbox',
    boxItem = 'pomnite_delivery_box',
    interactDistance = 2.0,
    serverDistance = 3.0,
    requireDuty = false,
    missionSeconds = 1800,
    cooldownSeconds = 60,
    maxLocations = 300,
    maxPurchase = 100,
    -- 仮の初期値。店舗登録時に変更できます。
    defaultReward = 400000,
    defaultPoints = 600,
    npcModel = 's_m_m_dockwork_01',
    gameplay = {
        handoverDuration = 2500,
        showGuide = true,
        carryBox = true,
        boxModel = 'prop_cs_cardbox_01',
    },
    -- 既存の料理素材を使う場合は item を導入済みアイテムIDに変更してください。
    products = {
        { id = 'normal', label = '普通の飲食物資', item = 'pomnite_food_supply', cash = 7500, points = 3 },
        -- 0 は価格未設定。現金価格・必要ポイントを設定すると購入できます。
        { id = 'premium', label = '高級な飲食物資', item = 'pomnite_premium_supply', cash = 12500, points = 5 },
        { id = 'sweet', label = '甘味の飲食物資', item = 'pomnite_sweet_supply', cash = 12500, points = 5 },
        { id = 'adult', label = '大人の飲食物資', item = 'pomnite_adult_supply', cash = 12500, points = 5 },
        { id = 'tobacco_leaf', label = 'タバコの葉', item = 'pomnite_tobacco_leaf', cash = 7500, points = 3 },
        { id = 'tea_leaf', label = '紅茶の茶葉', item = 'pomnite_tea_leaf', cash = 7500, points = 3 },
    },
    -- DBから書き出した配置をここへ移せます。id は重複させないでください。
    -- kind: market（商店NPC）, pickup（配達先NPC・箱受取）, shop（店舗NPC・受注/納品/ポイント交換）
    locations = {},
}
