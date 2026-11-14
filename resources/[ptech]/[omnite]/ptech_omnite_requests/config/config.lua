Config = {}

-- 全ボードで共通する設定です。
Config.InteractionDistance = 2.0
Config.RequestListLimit = 50
Config.RequestTitleMaxLength = 80
Config.RequestDescriptionMaxLength = 500

-- ボード内の表示文と通知文です。
Config.Text = {
    resourceTitle = '依頼ボード',
    openBoard = '依頼ボードを開く',
    createMission = '依頼を作成する',
    requestTitle = '依頼名',
    requestDescription = '内容',
    mode = '形式',
    acceptedMode = '受注型',
    deliveryMode = '納品型',
    open = '募集中',
    accepted = '受注中',
    completed = '完了',
    cancelled = '取消',
    acceptMission = '受注する',
    acceptedCount = '受注枠',
    deliverItems = '納品する',
    completeMission = '完了にする',
    cancelMission = '依頼を取り消す',
    refresh = '更新',
    close = '閉じる',
    noMissions = '現在、依頼はありません。',
    selectItem = '納品する品物',
    quantity = '数量',
    maxAcceptances = '受注枠数',
    maxQuantity = '最大納品数',
    remainingQuantity = '残り納品数',
    rewardPerItem = '1個あたりの報酬',
    missionCreated = '依頼を作成しました。',
    missionAccepted = '依頼を受注しました。',
    itemsDelivered = '納品しました。報酬を受け取りました。',
    missionCompleted = '依頼を完了しました。',
    missionCancelled = '依頼を取り消しました。',
    permissionDenied = 'この操作を行う権限がありません。',
    tooFar = '依頼ボードの近くで操作してください。',
    invalidInput = '入力内容を確認してください。',
    notAvailable = 'この依頼は現在操作できません。',
    notEnoughItems = '納品する品物が不足しています。',
    databaseNotReady = 'データベースの準備中です。少し待ってから再度お試しください。',
    playerInfoUnavailable = 'プレイヤー情報を取得できません。',
    boardNotFound = 'ボード設定が見つかりません。',
}

-- ボードの座標と権限は対象サーバーに合わせて設定します。
-- permission の view / post / accept / deliver / manage は個別に指定します。
-- 各ルールは public、jobs、gangs、citizenids を組み合わせて指定できます。
-- jobs / gangs の値は最低階級番号、または { minGrade = 0, onDuty = true } です。
Config.Boards = {
    --[[
    {
        id = 'restaurant_supply', -- ボードごとに一意なID
        label = '飲食店 依頼ボード',
        type = 'job', -- 'general' または 'job'
        coords = vec3(0.0, 0.0, 0.0), -- 対象サーバーの設置座標に置き換える
        size = vec3(1.2, 0.8, 1.5),
        rotation = 0.0,
        maxAcceptances = 5, -- 受注型依頼で指定できる最大の個別受注枠数
        maxDeliveryQuantity = 500, -- 納品型依頼で指定できる最大納品数
        deliveryPaymentType = 'cash', -- Qboxの 'cash' または 'bank'
        permissions = {
            view = { public = true },
            post = { jobs = { restaurant = { minGrade = 0 } } },
            accept = { public = true },
            deliver = { public = true },
            manage = { jobs = { restaurant = { minGrade = 3 } } },
        },
        deliveryItems = {
            -- アイテムIDと単価は対象サーバーのアイテム・経済設定に合わせる
            { name = 'water', label = '水', maxRewardPerItem = 10000 },
        },
        fields = {
            { key = 'item', label = '品物・作業', type = 'text', required = true, maxLength = 64 },
            { key = 'details', label = '補足', type = 'textarea', required = false, maxLength = 300 },
        },
    },
    ]]
}
