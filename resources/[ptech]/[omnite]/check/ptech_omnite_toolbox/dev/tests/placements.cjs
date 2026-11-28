const fs=require('node:fs'),path=require('node:path');
const parser=require('luaparse');
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
const root=path.resolve(__dirname,'../..');
const requests=path.resolve(root,'../ptech_omnite_requests');
function execute(state,text,name){
  parser.parse(text,{luaVersion:'5.3'});
  if(lauxlib.luaL_loadbuffer(state,to_luastring(text),null,to_luastring(name))!==lua.LUA_OK||lua.lua_pcall(state,0,0,0)!==lua.LUA_OK)throw Error(`${name}: ${to_jsstring(lua.lua_tostring(state,-1))}`);
}
for(const file of ['main/client/atms.lua','main/server/atms.lua','main/client/map_blips.lua','main/server/map_blips.lua'])parser.parse(fs.readFileSync(path.join(root,file),'utf8'),{luaVersion:'5.3'});
for(const file of ['config/config.lua','main/shared/shared.lua','main/client/boards.lua','main/client/client.lua','main/server/boards.lua','main/server/server.lua'])parser.parse(fs.readFileSync(path.join(requests,file),'utf8'),{luaVersion:'5.3'});
for(const kind of ['atm','board','mapblip']){
  const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
  execute(state,fs.readFileSync(path.join(__dirname,'placements_spec.lua'),'utf8'),'fixture');
  if(kind==='atm'){
    execute(state,fs.readFileSync(path.join(root,'config.lua'),'utf8'),'config');
    execute(state,fs.readFileSync(path.join(root,'main/server/atms.lua'),'utf8'),'atms');
    execute(state,'runATMSpecs()','ATM behavior');
    execute(state,fs.readFileSync(path.join(root,'main/server/atms.lua'),'utf8'),'atms reload');
    execute(state,"assert(next(callbacks['ptech_omnite_toolbox:atm:list'](1,true).points)==nil,'deleted ATM must stay deleted on restart')",'ATM restart');
  }else if(kind==='mapblip'){
    execute(state,fs.readFileSync(path.join(root,'config.lua'),'utf8'),'config');
    execute(state,fs.readFileSync(path.join(root,'main/server/map_blips.lua'),'utf8'),'map blips');
    execute(state,'runMapBlipSpecs()','map blip behavior');
    execute(state,fs.readFileSync(path.join(root,'main/server/map_blips.lua'),'utf8'),'map blips reload');
    execute(state,"local p=callbacks['ptech_omnite_toolbox:mapblip:list'](1).points; assert(p[mapSurvivorId] and p[mapSurvivorId].name=='Persistent' and p[mapSurvivorId].minimap==true,'saved blip and checkbox restore'); assert(p.legacy and p.legacy.minimap==false,'legacy DB blip defaults to main map only'); assert(not p[mapDeletedId],'deleted Config blip stays deleted')",'map blip restart');
  }else{
    execute(state,fs.readFileSync(path.join(requests,'config/config.lua'),'utf8'),'requests config');
    execute(state,fs.readFileSync(path.join(requests,'main/shared/shared.lua'),'utf8'),'requests shared');
    execute(state,fs.readFileSync(path.join(requests,'main/server/boards.lua'),'utf8'),'boards');
    execute(state,'runBoardSpecs()','board behavior');
    execute(state,fs.readFileSync(path.join(requests,'main/server/server.lua'),'utf8'),'requests server');
    execute(state,'threads[#threads](); runRequestSpecs()','single acceptance and request permissions');
    execute(state,fs.readFileSync(path.join(requests,'main/server/boards.lua'),'utf8'),'boards reload');
    execute(state,"assert(PTechRequests.GetBoard(savedBoard.id).label=='Updated','board restores latest persisted settings'); assert(PTechRequests.GetBoard(deletedBoardId)==nil,'deleted board stays deleted')",'board restart');
  }
  console.log(`PASS: ${kind} permissions, bucket isolation, validation, stale edits, DB failure and restart persistence`);
  const client=lauxlib.luaL_newstate();lualib.luaL_openlibs(client);
  execute(client,fs.readFileSync(path.join(__dirname,'placements_spec.lua'),'utf8'),'vector fixture');
  execute(client,fs.readFileSync(path.join(__dirname,'placement_clients_spec.lua'),'utf8'),'client fixture');
  if(kind==='atm'){
    execute(client,fs.readFileSync(path.join(root,'config.lua'),'utf8'),'ATM config');
    execute(client,fs.readFileSync(path.join(root,'main/client/atms.lua'),'utf8'),'ATM client');
    execute(client,'runATMClientSpecs()','ATM streaming and cleanup');
  }else if(kind==='mapblip'){
    execute(client,fs.readFileSync(path.join(root,'config.lua'),'utf8'),'map blip config');
    execute(client,fs.readFileSync(path.join(root,'main/client/map_blips.lua'),'utf8'),'map blip client');
    execute(client,'runMapBlipClientSpecs()','map blip rendering and cleanup');
  }else{
    execute(client,fs.readFileSync(path.join(requests,'config/config.lua'),'utf8'),'board config');
    execute(client,fs.readFileSync(path.join(requests,'main/client/boards.lua'),'utf8'),'board client');
    execute(client,'runBoardClientSpecs()','board targets and cleanup');
  }
  console.log(`PASS: ${kind} client synchronization, management entry and resource cleanup`);
}
