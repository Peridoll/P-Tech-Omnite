const fs=require('node:fs'),path=require('node:path');
const parser=require('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=path.resolve(__dirname,'../..');
for(const side of ['server','client']){
    const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
    for(const file of [`dev/tests/vehicle_clone_${side}_spec.lua`,'config.lua',`main/${side}/vehicle_clone.lua`]){
        const code=fs.readFileSync(path.join(root,file),'utf8');parser.parse(code,{luaVersion:'5.3'});
        if(lauxlib.luaL_loadbuffer(L,to_luastring(code),null,to_luastring(file))!==lua.LUA_OK||lua.lua_pcall(L,0,0,0)!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
    }
    if(lauxlib.luaL_dostring(L,to_luastring('runVehicleCloneSpecs()'))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
    console.log(`PASS: vehicle clone ${side} behavior`);
}
