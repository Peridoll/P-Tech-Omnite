-- 導入先: ox_inventory/data/items.lua の return { ... } 内へ追加してください。
-- 同じIDが既にある場合は重複追加せず、既存定義と照合してください。反映後はox_inventoryを再起動します。
-- 素材画像はGit上の直接URLを使用します。
['pomnite_delivery_box']   = {
  label = '店舗配達用の箱', weight = 3000, stack = false, close = true, consume = 0, client = { image = 'https://raw.githubusercontent.com/Peridoll/P-Tech-Omnite/feature/dev/resources/%5Bptech%5D/%5Bomnite%5D/ptech_omnite_delivery/install/image/pomnite_delivery_box.png' } },
['pomnite_food_supply']    = {
  label = '普通の飲食物資', weight = 100,  stack = true, close = true, client = { image = 'https://raw.githubusercontent.com/Peridoll/P-Tech-Omnite/feature/dev/resources/%5Bptech%5D/%5Bomnite%5D/ptech_omnite_delivery/install/image/pomnite_food_supply.png' } },
['pomnite_premium_supply'] = {
  label = '高級な飲食物資', weight = 100,  stack = true, close = true, client = { image = 'https://raw.githubusercontent.com/Peridoll/P-Tech-Omnite/feature/dev/resources/%5Bptech%5D/%5Bomnite%5D/ptech_omnite_delivery/install/image/pomnite_premium_supply.png' } },
['pomnite_sweet_supply']   = {
  label = '甘味の飲食物資', weight = 100,  stack = true, close = true, client = { image = 'https://raw.githubusercontent.com/Peridoll/P-Tech-Omnite/feature/dev/resources/%5Bptech%5D/%5Bomnite%5D/ptech_omnite_delivery/install/image/pomnite_sweet_supply.png' } },
  ['pomnite_tea_leaf']       = {
    label = '紅茶の茶葉',     weight = 100,  stack = true, close = true, client = { image = 'https://raw.githubusercontent.com/Peridoll/P-Tech-Omnite/feature/dev/resources/%5Bptech%5D/%5Bomnite%5D/ptech_omnite_delivery/install/image/pomnite_tea_leaf.png' } },
  ['pomnite_tobacco_leaf']   = {
    label = 'タバコの葉',     weight = 100,  stack = true, close = true, client = { image = 'https://raw.githubusercontent.com/Peridoll/P-Tech-Omnite/feature/dev/resources/%5Bptech%5D/%5Bomnite%5D/ptech_omnite_delivery/install/image/pomnite_tobacco_leaf.png' } },
