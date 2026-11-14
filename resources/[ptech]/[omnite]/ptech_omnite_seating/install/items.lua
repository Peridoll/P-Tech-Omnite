-- ox_inventory/data/items.lua のreturnテーブル内へ追加。
-- 配置ごとには消費しません。ショップ・クラフト・ドロップへ追加しないでください。
['pomnite_toolbox'] = {
    label = 'Omini工具箱',
    weight = 100,
    stack = false,
    close = true,
    consume = 0,
    server = { export = 'ptech_omnite_seating.usePlacementTool' },
},
