const fs=require('node:fs'),path=require('node:path');
const parser=require('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=path.resolve(__dirname,'..');
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
for(const file of ['dev/tests/shop_server_spec.lua','config.lua','main/server/shops.lua']){
    const source=fs.readFileSync(path.join(root,file),'utf8');
    parser.parse(source,{luaVersion:'5.3'});
    if(lauxlib.luaL_dostring(L,to_luastring(source))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
}
parser.parse(fs.readFileSync(path.join(root,'main/client/shops.lua'),'utf8'),{luaVersion:'5.3'});
if(lauxlib.luaL_dostring(L,to_luastring('runShopSpecs()'))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
console.log('PASS: shop management permissions, metadata, layout, finite/unlimited stock, cash sales, proceeds access and deletion returns');

const clientState=lauxlib.luaL_newstate();lualib.luaL_openlibs(clientState);
for(const file of ['dev/tests/shop_client_spec.lua','config.lua','main/client/shops.lua']){
    const source=fs.readFileSync(path.join(root,file),'utf8');
    parser.parse(source,{luaVersion:'5.3'});
    if(lauxlib.luaL_dostring(clientState,to_luastring(source))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(clientState,-1)));
}
if(lauxlib.luaL_dostring(clientState,to_luastring('runShopClientSpecs()'))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(clientState,-1)));
console.log('PASS: direct shop and replenishment targets, job grades, product prices and configurable vault access');

for(const suite of ['runShopLifecycleSpecs','runShopSyncSpecs']){
const lifecycle=lauxlib.luaL_newstate();lualib.luaL_openlibs(lifecycle);
for(const file of ['dev/tests/shop_lifecycle_spec.lua','config.lua','main/client/shops.lua']){
    const source=fs.readFileSync(path.join(root,file),'utf8');
    parser.parse(source,{luaVersion:'5.3'});
    if(lauxlib.luaL_dostring(lifecycle,to_luastring(source))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(lifecycle,-1)));
}
if(lauxlib.luaL_dostring(lifecycle,to_luastring(suite+'()'))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(lifecycle,-1)));
}
console.log('PASS: shop NPC protection, deleted/dead entity recovery, streaming, failed creation/targets, stale loads and logout cleanup');
console.log('PASS: approach refresh, periodic recovery, silent initial-sync retries, instance changes, hidden NPC repair and independent model loading');

if(process.argv[2]) {
    const patch=require('../install/patch-ox-shop-prices.cjs');
    const original=fs.readFileSync(path.join(process.argv[2],'modules/shops/server.lua'),'utf8');
    const patched=patch(original);
    if(patch(patched)!==patched)throw Error('Patch must be idempotent');
    const setup=patched.slice(patched.indexOf('local function setupShopItems'),patched.indexOf('local function createShop'));
    const check=`local Shops={} local locations='locations' local server={randomprices=true}
local Items=function(name) return {name=name,weight=1} end
local Inventory={SlotWeight=function() return 1 end}
math.random=function() return 120 end
`+setup+`
registerShopType('fixed',{name='Fixed',randomprices=false,inventory={{name='water',price=25000,currency='money'}}})
assert(Shops.fixed.items[1].price==25000,'fixed shop retains configured price with random prices enabled')
registerShopType('normal',{name='Normal',inventory={{name='water',price=25000,currency='money'}}})
assert(Shops.normal.items[1].price==30000,'normal shops retain price randomisation')
`;
    const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
    if(lauxlib.luaL_dostring(state,to_luastring(check))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(state,-1)));
    console.log('PASS: actual ox_inventory registration retains fixed prices and preserves other shops');
}
