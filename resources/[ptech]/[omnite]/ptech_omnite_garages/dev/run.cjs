const fs=require('node:fs'),path=require('node:path');
const parser=require('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=path.resolve(__dirname,'..');
for(const file of ['fxmanifest.lua','config.lua','main/client.lua','main/server.lua']) parser.parse(fs.readFileSync(path.join(root,file),'utf8'),{luaVersion:'5.3'});
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
function run(text,name){if(lauxlib.luaL_loadbuffer(L,to_luastring(text),null,to_luastring(name))!==lua.LUA_OK || lua.lua_pcall(L,0,0,0)!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));}
run(fs.readFileSync(path.join(__dirname,'garage_spec.lua'),'utf8'),'garage_spec');
run(fs.readFileSync(path.join(root,'main/client.lua'),'utf8'),'garage_client');
run('runGarageSpecs()','garage_assertions');
run("local captured; exports={ox_inventory={GetItemCount=function(_,src,item) assert(item=='pomnite_toolbox') return src==1 and 1 or 0 end}}; lib.callback.register=function(name,fn) captured=fn end; function verifyGarageAuth() assert(captured(1) and not captured(2)) end",'server_fixture');
run(fs.readFileSync(path.join(root,'main/server.lua'),'utf8'),'garage_server');run('verifyGarageAuth()','server_assertions');
console.log('PASS: garage syntax, existing spawn preservation, coordinate export, tool authorization and JG version guard');
