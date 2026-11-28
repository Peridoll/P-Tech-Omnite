const fs=require('node:fs');
const path=require('node:path');
const {createRequire}=require('node:module');
let deps=require;
try { require.resolve('fengari'); }
catch { deps=createRequire(path.resolve(__dirname,'../../../../../.omnite-checks/check.cjs')); }
const parser=deps('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=deps('fengari');
const state=lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
for(const file of ['dev/gameplay_spec.lua','config.lua','main/gameplay.lua']) {
    const source=fs.readFileSync(path.resolve(__dirname,'..',file),'utf8');
    parser.parse(source,{luaVersion:'5.3'});
    if(lauxlib.luaL_loadbuffer(state,to_luastring(source),null,to_luastring(file))!==lua.LUA_OK || lua.lua_pcall(state,0,0,0)!==lua.LUA_OK)
        throw Error(to_jsstring(lua.lua_tostring(state,-1)));
}
if(lauxlib.luaL_dostring(state,to_luastring('runGameplaySpecs()'))!==lua.LUA_OK) throw Error(to_jsstring(lua.lua_tostring(state,-1)));
console.log('PASS: gameplay handovers, cancellation, carry prop, vehicle/death/inventory transitions, stale loads, shared UI and cleanup');
