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
    defaultReward = 10000,
    defaultPoints = 1,
    npcModel = 's_m_m_dockwork_01',
    -- 既存の料理素材を使う場合は item を導入済みアイテムIDに変更してください。
    products = {
        { id = 'normal', label = '普通の飲食物資', item = 'pomnite_food_supply', cash = 7500, points = 1 },
        -- 0 は価格未設定。現金価格・必要ポイントを設定すると購入できます。
        { id = 'premium', label = '高級な飲食物資', item = 'pomnite_premium_supply', cash = 0, points = 0 },
        { id = 'rich', label = '豊富な飲食物資', item = 'pomnite_rich_supply', cash = 0, points = 0 },
        { id = 'sweet', label = '甘味の飲食物資', item = 'pomnite_sweet_supply', cash = 0, points = 0 },
        { id = 'spicy', label = '辛味の飲食物資', item = 'pomnite_spicy_supply', cash = 0, points = 0 },
        { id = 'dry', label = '乾物の飲食物資', item = 'pomnite_dry_supply', cash = 12500, points = 1 },
        { id = 'adult', label = '大人の飲食物資', item = 'pomnite_adult_supply', cash = 12500, points = 1 },
    },
    -- DBから書き出した配置をここへ移せます。id は重複させないでください。
    -- kind: shop（受注・納品・ポイント交換）, pickup（集荷）, market（ボス現金購入）
    locations = {},
}
