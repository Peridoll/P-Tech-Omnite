const fs=require('node:fs'),path=require('node:path');
const parser=require('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=path.resolve(__dirname,'..');
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
for(const file of ['dev/tests/shop_server_spec.lua','main/server/shops.lua']){
    const source=fs.readFileSync(path.join(root,file),'utf8');
    parser.parse(source,{luaVersion:'5.3'});
    if(lauxlib.luaL_dostring(L,to_luastring(source))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
}
parser.parse(fs.readFileSync(path.join(root,'main/client/shops.lua'),'utf8'),{luaVersion:'5.3'});
if(lauxlib.luaL_dostring(L,to_luastring('runShopSpecs()'))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
console.log('PASS: shop management permissions, metadata, layout, finite/unlimited stock, cash sales, proceeds access and deletion returns');
