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
for (const file of ['config.lua','fxmanifest.lua','main/client.lua','main/server.lua']) {
    parser.parse(fs.readFileSync(path.join(root,file),'utf8'),{luaVersion:'5.3'});
}
parser.parse('return {'+fs.readFileSync(path.join(root,'install/items.lua'),'utf8')+'}',{luaVersion:'5.3'});
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
for (const file of ['dev/server_spec.lua','config.lua','main/server.lua']) {
    const source=fs.readFileSync(path.join(root,file),'utf8');
    if (lauxlib.luaL_loadbuffer(state,to_luastring(source),null,to_luastring(file))!==lua.LUA_OK || lua.lua_pcall(state,0,0,0)!==lua.LUA_OK)
        throw new Error(to_jsstring(lua.lua_tostring(state,-1)));
}
if (lauxlib.luaL_dostring(state,to_luastring('runSpecs()'))!==lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(state,-1)));
console.log('PASS: delivery Lua syntax, job permissions, distance, duplicate requests, inventory failures, shared points, boss purchases and persistence failures');
const client = lauxlib.luaL_newstate();
lualib.luaL_openlibs(client);
for (const file of ['dev/client_spec.lua','config.lua','main/client.lua']) {
    const source=fs.readFileSync(path.join(root,file),'utf8');
    if (lauxlib.luaL_loadbuffer(client,to_luastring(source),null,to_luastring(file))!==lua.LUA_OK || lua.lua_pcall(client,0,0,0)!==lua.LUA_OK)
        throw new Error(to_jsstring(lua.lua_tostring(client,-1)));
}
if (lauxlib.luaL_dostring(client,to_luastring('runClientSpecs()'))!==lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(client,-1)));
console.log('PASS: delivery NPC targets, route stages, role visibility, manager, config export and cleanup');
