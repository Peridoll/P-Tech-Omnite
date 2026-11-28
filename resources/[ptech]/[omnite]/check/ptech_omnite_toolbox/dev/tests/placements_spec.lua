callbacks,threads={},{}
local rows,encoded={},{}
local sequence=0
admin,tool,bucket,dbFailure=true,true,0,false
local mt={}
mt.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end
mt.__len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local position=vec3(1,2,3)
local function clone(v)
    if type(v)~='table' then return v end
    local c={} for k,x in pairs(v) do c[k]=clone(x) end return c
end
json={encode=function(value) sequence=sequence+1 local key='encoded'..sequence encoded[key]=clone(value) return key end,
    decode=function(value) if value=='false' then return false end if value=='{}' then return {} end return clone(encoded[value]) end}
SeatingServer={finite=function(n,max) return type(n)=='number' and n==n and math.abs(n)<=max end}
lib={callback={register=function(name,fn) callbacks[name]=fn end}}
exports={ox_inventory={GetItemCount=function() return tool and 1 or 0 end},qbx_core={GetPlayer=function() return {PlayerData={citizenid='person',job={name='ambulance',grade={level=2}},charinfo={firstname='Test'}}} end}}
function IsPlayerAceAllowed() return admin end
function GetPlayerRoutingBucket() return bucket end
function GetPlayerPed() return 1 end
function GetEntityCoords() return position end
function GetEntityHeading() return 90 end
function GetPlayers() return {'1'} end
function TriggerClientEvent() end
function CreateThread(fn) threads[#threads+1]=fn end
function AddEventHandler() end
local function query(sql,args)
    if dbFailure then error('expected DB failure') end
    if sql:find('SELECT %* FROM') then
        local result={} for id,row in pairs(rows) do result[#result+1]={id=id,payload=row.payload,revision=row.revision} end return result
    end
    if sql:find('INSERT INTO ptech_omnite_atms',1,true) or sql:find('INSERT INTO ptech_omnite_request_boards',1,true) or sql:find('INSERT INTO ptech_omnite_map_blips',1,true) then
        local tombstone=sql:find("'false'",1,true)
        rows[args[1]]={payload=tombstone and 'false' or args[2],revision=tombstone and args[2] or args[3] or 1}
        return 1
    end
    if sql:find('SELECT id, board_id',1,true) then return {} end
    return {}
end
function runMapBlipSpecs()
    local prefix='ptech_omnite_toolbox:mapblip:'
    local list,save,delete=callbacks[prefix..'list'],callbacks[prefix..'save'],callbacks[prefix..'delete']
    local input={name='Hospital',sprite=61,colour=2,scale=0.8,shortRange=false,enabled=true,coords={x=999,y=999,z=999}}
    admin=false assert(not save(1,input).ok and not list(1,true).ok) admin=true
    tool=false assert(not save(1,input).ok) tool=true
    input.sprite=1.5 assert(not save(1,input).ok) input.sprite=61
    input.colour=256 assert(not save(1,input).ok) input.colour=2
    input.scale=0/0 assert(not save(1,input).ok) input.scale=0.8
    input.shortRange='true' assert(not save(1,input).ok) input.shortRange=false
    input.minimap='true' assert(not save(1,input).ok) input.minimap=nil
    dbFailure=true assert(not save(1,input).ok) dbFailure=false
    local result=save(1,input) assert(result.ok)
    local id=result.id local p=list(1).points[id]
    assert(p.coords.x==1 and p.coords.y==2,'server captures actual player coordinates')
    assert(p.sprite==61 and p.colour==2 and p.shortRange==true and p.minimap==false and p.enabled and p.revision==1,'missing checkbox defaults to main map only')
    Config.MapBlips.maxTotal=1 assert(not save(1,input).ok,'placement limit enforced') Config.MapBlips.maxTotal=500
    bucket=1 assert(next(list(1).points)==nil and not delete(1,id,1).ok) bucket=0
    input.id,input.revision=id,0 assert(not save(1,input).ok)
    input.revision=1 input.name='Updated' input.enabled=false input.shortRange=true input.minimap=true
    dbFailure=true assert(not save(1,input).ok) dbFailure=false
    assert(save(1,input).ok)
    p=list(1).points[id] assert(p.revision==2 and not p.enabled and not p.shortRange and p.minimap and p.coords.x==1,'minimap always-on overrides short range')
    assert(not delete(1,id,1).ok)
    Config.MapBlips.fixed={p}
    dbFailure=true assert(not delete(1,id,2).ok) dbFailure=false
    assert(delete(1,id,2).ok and not list(1).points[id])
    mapDeletedId=id
    input.id,input.revision=nil,nil input.name='Persistent' input.enabled=true
    local survivor=save(1,input) assert(survivor.ok) mapSurvivorId=survivor.id
    local legacy=clone(list(1).points[mapSurvivorId]) legacy.minimap=nil legacy.shortRange=false
    rows.legacy={payload=json.encode(legacy),revision=1}
end
MySQL={ready=function(fn) fn() end,query={await=query},scalar={await=function() sequence=sequence+1 return 'uuid'..sequence end},insert={await=query}}
function runATMSpecs()
    local list,save,delete=callbacks['ptech_omnite_toolbox:atm:list'],callbacks['ptech_omnite_toolbox:atm:save'],callbacks['ptech_omnite_toolbox:atm:delete']
    local input={name='Test ATM',model='prop_atm_01',coords={x=1,y=2,z=2},heading=90}
    admin=false assert(not save(1,input).ok and not list(1,true).ok)
    admin=true tool=false assert(not save(1,input).ok)
    tool=true input.model='invalid' assert(not save(1,input).ok)
    input.model='prop_atm_01' input.heading=0/0 assert(not save(1,input).ok)
    input.heading=90 dbFailure=true assert(not save(1,input).ok) dbFailure=false
    assert(save(1,input).ok)
    local id,p=next(list(1,true).points) assert(id and p.revision==1)
    bucket=1 assert(next(list(1).points)==nil) assert(not delete(1,id,1).ok) bucket=0
    local changed={id=id,revision=0,name='Updated',model='prop_atm_02',relocate=false}
    assert(not save(1,changed).ok)
    changed.revision=1 dbFailure=true assert(not save(1,changed).ok) dbFailure=false
    assert(save(1,changed).ok and list(1).points[id].revision==2)
    assert(not delete(1,id,1).ok)
    assert(delete(1,id,2).ok and next(list(1).points)==nil)
end
function runBoardSpecs()
    local list,save,delete=callbacks['ptech_omnite_requests:boards:list'],callbacks['ptech_omnite_requests:boards:save'],callbacks['ptech_omnite_requests:boards:delete']
    local input={label='General board',type='general',permissions={view={public=true},post={citizenids={'person'}},accept={jobs={ambulance={minGrade=1,onDuty=true}}},deliver={public=true},manage={jobs={ambulance=2}}}}
    admin=false assert(not save(1,input).ok) admin=true tool=false assert(not save(1,input).ok) tool=true
    input.permissions.manage.jobs.ambulance=-1 assert(not save(1,input).ok) input.permissions.manage.jobs.ambulance=2
    dbFailure=true assert(not save(1,input).ok) dbFailure=false assert(save(1,input).ok)
    local p=list(1,true).boards[1] assert(p and p.maxAcceptances==1 and p.permissions.accept.jobs.ambulance.onDuty)
    bucket=1 assert(#list(1).boards==0 and not delete(1,p.id,1).ok) bucket=0
    input.id,input.revision=p.id,0 assert(not save(1,input).ok)
    input.revision=1 input.label='Updated' assert(save(1,input).ok)
    savedBoard=list(1).boards[1] assert(savedBoard.revision==2)
    input.id,input.revision=nil,nil assert(save(1,input).ok)
    for _,board in ipairs(list(1).boards) do if board.id~=savedBoard.id then deletedBoardId=board.id end end
    assert(delete(1,deletedBoardId,1).ok)
    local copy=PTechRequests.ToLua(list(1).boards) assert(load('return '..copy),'export is valid Lua')
end
function runRequestSpecs()
    local prefix='ptech_omnite_requests:'
    local p=savedBoard
    -- 勤務必須の受注条件を満たさない場合は拒否します。
    assert(not callbacks[prefix..'acceptRequest'](1,p.id,1).ok)
    p.permissions.accept.jobs.ambulance.onDuty=false
    local acceptedCount,insertCount=0,0
    MySQL.update={await=function(sql)
        assert(sql:find('accepted_count = 0',1,true),'server enforces a single assignee')
        if acceptedCount>0 then return 0 end acceptedCount=1 return 1
    end}
    MySQL.insert.await=function(sql,args)
        insertCount=insertCount+1
        if sql:find('created_name',1,true) then assert(args[9]==1,'forged multi-assignee payload is ignored') end
        return 1
    end
    assert(callbacks[prefix..'acceptRequest'](1,p.id,1).ok)
    assert(not callbacks[prefix..'acceptRequest'](1,p.id,1).ok and insertCount==1,'second assignee is refused')
    assert(not callbacks[prefix..'acceptRequest'](1,p.id,0/0).ok)
    bucket=1 assert(not callbacks[prefix..'getBoard'](1,p.id).ok) bucket=0
    assert(callbacks[prefix..'createRequest'](1,p.id,{title='Test',mode='accepted',maxAcceptances=99}).ok)
end
