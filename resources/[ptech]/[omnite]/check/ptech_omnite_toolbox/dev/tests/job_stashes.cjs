const fs=require('node:fs'),path=require('node:path');
const parser=require('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=path.resolve(__dirname,'../..');
for(const side of ['server','client']){
    const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
    const run=(code,name)=>{
        parser.parse(code,{luaVersion:'5.3'});
        if(lauxlib.luaL_loadbuffer(state,to_luastring(code),null,to_luastring(name))!==lua.LUA_OK||lua.lua_pcall(state,0,0,0)!==lua.LUA_OK)throw Error(`${name}: ${to_jsstring(lua.lua_tostring(state,-1))}`);
    };
    for(const file of [`dev/tests/job_stashes_${side}_spec.lua`,'config.lua',`main/${side}/job_stashes.lua`])run(fs.readFileSync(path.join(root,file),'utf8'),file);
    run('runJobStashSpecs()','job stash assertions');
    if(side==='server'){
        run(fs.readFileSync(path.join(root,'main/server/job_stashes.lua'),'utf8'),'job stash reload');
        run('runJobStashReloadSpecs()','job stash restart assertions');
    }
    console.log(`PASS: job stash ${side} behavior`);
}
