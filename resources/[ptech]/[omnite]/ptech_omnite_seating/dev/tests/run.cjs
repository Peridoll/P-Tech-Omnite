const fs = require('node:fs');
const path = require('node:path');
const parser = require('luaparse');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.resolve(__dirname, '../..');
for (const file of ['config.lua', 'fxmanifest.lua', 'main/client/client.lua', 'main/client/placement.lua', 'main/server/server.lua', 'main/server/placement.lua']) {
  parser.parse(fs.readFileSync(path.join(root, file), 'utf8'), { luaVersion: '5.3' });
}
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(text, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(text), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
}
run(fs.readFileSync(path.join(__dirname, 'server_spec.lua'), 'utf8'), 'server_spec');
for (const file of ['config.lua', 'main/server/server.lua', 'main/server/placement.lua']) run(fs.readFileSync(path.join(root, file), 'utf8'), file);
run('runSpecs()', 'assertions');
console.log('PASS: Lua syntax and server behavior');
