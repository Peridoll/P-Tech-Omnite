const fs = require('node:fs');
const path = require('node:path');

function patchShopPrices(source) {
  if (source.includes('-- omnite: per-shop fixed prices')) return source;
  const changes = [
    ['(server.randomprices and (not slot.currency', '(server.randomprices and shop.randomprices ~= false and (not slot.currency'],
    ['\t\t\titems = properties.inventory,', '\t\t\t-- omnite: per-shop fixed prices\n\t\t\trandomprices = properties.randomprices,\n\t\t\titems = properties.inventory,'],
    ['\t\titems = table.clone(shop.inventory),', '\t\trandomprices = shop.randomprices,\n\t\titems = table.clone(shop.inventory),'],
  ];
  for (const [before, after] of changes) {
    if (source.split(before).length !== 2) throw new Error('Unsupported ox_inventory shops source: ' + before);
    source = source.replace(before, () => after);
  }
  return source;
}

module.exports = patchShopPrices;
if (require.main === module) {
  const root = process.argv[2];
  if (!root) throw new Error('Usage: node patch-ox-shop-prices.cjs <ox_inventory directory>');
  const file = path.resolve(root, 'modules', 'shops', 'server.lua');
  const source = fs.readFileSync(file, 'utf8');
  const result = patchShopPrices(source);
  if (result === source) console.log('Already patched: ' + file);
  else {
    fs.writeFileSync(file + '.omnite-' + Date.now() + '.bak', source, { flag: 'wx' });
    fs.writeFileSync(file, result);
    console.log('Patched: ' + file);
  }
}
