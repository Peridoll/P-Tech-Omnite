-- ox_inventory/data/items.lua のreturnテーブル内へ追加。
-- 配置ごとには消費しません。ショップ・クラフト・ドロップへ追加しないでください。
['pomnite_toolbox'] = {
    label = 'Omini工具箱',
    weight = 100, stack = false, close = true, consume = 0,
    server = { export = 'ptech_omnite_seating.usePlacementTool' },
    client = {
      image = 'https://raw.githubusercontent.com/Peridoll/P-Tech-Omnite/4586dbb6639f8b2c3fb4fd21bdf36ac3598f14e4/resources/%5Bptech%5D/%5Bomnite%5D/ptech_omnite_seating/install/image/pomnite_toolbox.png',
    },
  },
