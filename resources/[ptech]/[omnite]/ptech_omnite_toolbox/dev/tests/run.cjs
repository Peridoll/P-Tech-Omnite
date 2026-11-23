const fs = require('node:fs');
const path = require('node:path');
const parser = require('luaparse');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.resolve(__dirname, '../..');
for (const file of ['config.lua', 'fxmanifest.lua', 'main/client/exit.lua', 'main/client/client.lua', 'main/client/placement.lua', 'main/server/server.lua', 'main/server/placement.lua', 'main/client/teleporters.lua', 'main/server/teleporters.lua']) {
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
const client = lauxlib.luaL_newstate();
lualib.luaL_openlibs(client);
function clientRun(text, name) {
  if (lauxlib.luaL_loadbuffer(client, to_luastring(text), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(client, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(client, -1)));
  }
}
clientRun(fs.readFileSync(path.join(__dirname, 'toolbox_spec.lua'), 'utf8'), 'toolbox_spec');
clientRun(fs.readFileSync(path.join(root, 'main/client/placement.lua'), 'utf8'), 'placement_client');
clientRun('runToolboxSpecs()', 'toolbox_assertions');
parser.parse('return {' + fs.readFileSync(path.join(root, 'install/items.lua'), 'utf8') + '}', {luaVersion:'5.3'});
console.log('PASS: toolbox use, cancellation, authorization and busy state');
const editor = lauxlib.luaL_newstate();
lualib.luaL_openlibs(editor);
function editorRun(text, name) {
  if (lauxlib.luaL_loadbuffer(editor, to_luastring(text), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(editor, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(editor, -1)));
  }
}
editorRun(fs.readFileSync(path.join(__dirname, 'editor_spec.lua'), 'utf8'), 'editor_spec');
editorRun(fs.readFileSync(path.join(root, 'config.lua'), 'utf8'), 'config');
editorRun(fs.readFileSync(path.join(root, 'main/client/placement.lua'), 'utf8'), 'placement_client');
editorRun('runEditorSpecs()', 'editor_assertions');
console.log('PASS: management markers, E create/edit/delete, MLO selection, medical types, sliders and ALT');
const sitting = lauxlib.luaL_newstate();
lualib.luaL_openlibs(sitting);
function sittingRun(text, name) {
  if (lauxlib.luaL_loadbuffer(sitting, to_luastring(text), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(sitting, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(sitting, -1)));
  }
}
sittingRun(fs.readFileSync(path.join(__dirname,'sitting_spec.lua'),'utf8'),'sitting_spec');
sittingRun(fs.readFileSync(path.join(root,'config.lua'),'utf8'),'config');
sittingRun(fs.readFileSync(path.join(root,'main/client/client.lua'),'utf8'),'seating_client');
sittingRun('runSittingSpecs()','sitting_assertions');
console.log('PASS: chair/counter/bed G menus, personal style changes and stale menu protection');
const exitHelper=fs.readFileSync(path.join(root,'main/client/client.lua'),'utf8').split('local occupiedSeats')[0];
sittingRun(exitHelper+'\n'+fs.readFileSync(path.join(__dirname,'safe_exit_spec.lua'),'utf8')+'\nrunSafeExitSpecs()','safe_exit_assertions');
console.log('PASS: exit floor and clearance checks, blocked routes, and cancelled search');
for (const side of ['server', 'client']) {
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  const execute = (text, name) => {
    if (lauxlib.luaL_loadbuffer(state, to_luastring(text), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(state, 0, 0, 0) !== lua.LUA_OK) {
      throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
    }
  };
  execute(fs.readFileSync(path.join(__dirname, `teleport_${side}_spec.lua`), 'utf8'), `teleport_${side}_spec`);
  execute(fs.readFileSync(path.join(root, 'config.lua'), 'utf8'), 'config');
  execute(fs.readFileSync(path.join(root, `main/${side}/teleporters.lua`), 'utf8'), `teleport_${side}`);
  execute('runTeleportSpecs()', `teleport_${side}_assertions`);
  console.log(`PASS: teleporter ${side} behavior`);
}
