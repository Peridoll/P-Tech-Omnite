const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
// Reuse the repository's existing local check dependencies; no downloads required.
let deps;
try { deps = require; require.resolve('fengari'); }
catch { deps = createRequire(path.resolve(__dirname, '../../../../../.omnite-checks/check.cjs')); }
const parser = deps('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring} = deps('fengari');
const root = path.resolve(__dirname,'..');
for (const file of ['config.lua','fxmanifest.lua','main/gameplay.lua','main/client.lua','main/server.lua','main/finance.lua']) {
    parser.parse(fs.readFileSync(path.join(root,file),'utf8'),{luaVersion:'5.3'});
}
parser.parse('return {'+fs.readFileSync(path.join(root,'install/items.lua'),'utf8')+'}',{luaVersion:'5.3'});
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
for (const file of ['dev/v2_spec.lua','config.lua','main/server.lua']) {
    const source=fs.readFileSync(path.join(root,file),'utf8');
    if (lauxlib.luaL_loadbuffer(state,to_luastring(source),null,to_luastring(file))!==lua.LUA_OK || lua.lua_pcall(state,0,0,0)!==lua.LUA_OK)
        throw new Error(to_jsstring(lua.lua_tostring(state,-1)));
}
if (lauxlib.luaL_dostring(state,to_luastring('runSpecs()'))!==lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(state,-1)));
const reload=fs.readFileSync(path.join(root,'main/server.lua'),'utf8');
if(lauxlib.luaL_dostring(state,to_luastring(reload))!==lua.LUA_OK || lauxlib.luaL_dostring(state,to_luastring('verifyCatalogReload()'))!==lua.LUA_OK)
    throw new Error(to_jsstring(lua.lua_tostring(state,-1)));
console.log('PASS: catalog CRUD, stale edits, shop account isolation, database failures and restart restoration');
console.log('PASS: delivery Lua syntax, job permissions, distance, duplicate requests, inventory failures, store points, boss vault access and persistence failures');
const client = lauxlib.luaL_newstate();
lualib.luaL_openlibs(client);
for (const file of ['dev/client_spec.lua','config.lua','main/client.lua']) {
    const source=fs.readFileSync(path.join(root,file),'utf8');
    if (lauxlib.luaL_loadbuffer(client,to_luastring(source),null,to_luastring(file))!==lua.LUA_OK || lua.lua_pcall(client,0,0,0)!==lua.LUA_OK)
        throw new Error(to_jsstring(lua.lua_tostring(client,-1)));
}
if (lauxlib.luaL_dostring(client,to_luastring('runClientSpecs()'))!==lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(client,-1)));
console.log('PASS: delivery NPC targets, route stages, role visibility, manager, config export and cleanup');

const finance=lauxlib.luaL_newstate();lualib.luaL_openlibs(finance);
for(const file of ['dev/finance_spec.lua','main/finance.lua']){
    const code=fs.readFileSync(path.join(root,file),'utf8');
    if(lauxlib.luaL_dostring(finance,to_luastring(code))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(finance,-1)));
}
if(lauxlib.luaL_dostring(finance,to_luastring('runFinanceSpecs()'))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(finance,-1)));
console.log('PASS: escrow reservation, idempotent refunds, store credit isolation, restart recovery and uncertain-transfer quarantine');
