const fs=require('node:fs'),path=require('node:path');
const parser=require('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=path.resolve(__dirname,'../..');
for(const side of ['server','client']){
    const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
    function run(code,name){
        parser.parse(code,{luaVersion:'5.3'});
        if(lauxlib.luaL_loadbuffer(L,to_luastring(code),null,to_luastring(name))!==lua.LUA_OK||lua.lua_pcall(L,0,0,0)!==lua.LUA_OK)throw Error(`${name}: ${to_jsstring(lua.lua_tostring(L,-1))}`);
    }
    for(const file of [`dev/tests/treasure_${side}_spec.lua`,'config.lua',`main/${side}/treasure.lua`])run(fs.readFileSync(path.join(root,file),'utf8'),file);
    run('runTreasureSpecs()','treasure assertions');
    if(side==='server'){
        run(fs.readFileSync(path.join(root,'main/server/treasure.lua'),'utf8'),'treasure server reload');
        run('runTreasureReloadSpecs()','restart assertions');
    }
    console.log(`PASS: treasure ${side} behavior`);
}
