local events,contexts,tasks={},{},{}
local zones={}
local nextZone=0
local opened,saved,checked
local role={name='ambulance',grade={level=1}}
local point={id='one',name='EMS Locker',job='ambulance',minGrade=2,slots=100,maxWeight=500000,enabled=true,coords={x=1,y=2,z=10},revision=1}
local points={one=point}
SeatingClient={}
lib={notify=function() end,registerContext=function(c) contexts[c.id]=c end,showContext=function() end,
    inputDialog=function() return {'Shared items','ambulance',0,100,500,true,true} end,
    callback={await=function(name,_,...)
        local args={...}
        if name=='ptech_omnite_toolbox:jobstash:list' then return {ok=true,points=points,jobs={ambulance={label='EMS'}}} end
        if name=='ptech_omnite_toolbox:jobstash:open' then return {ok=true,inventory='shared_id'} end
        assert(name=='ptech_omnite_toolbox:jobstash:save') saved=args[1] return {ok=true}
    end}}
exports={qbx_core={GetPlayerData=function() return {job=role} end},ox_target={
    addBoxZone=function(_,zone) nextZone=nextZone+1 zones[nextZone]=zone return nextZone end,
    removeZone=function(_,id) zones[id]=nil end,
},ox_inventory={openInventory=function(_,kind,id) opened={kind=kind,id=id} end}}
function vec3(x,y,z) return {x=x,y=y,z=z} end
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) events[name]=fn end
function CreateThread(fn) tasks[#tasks+1]=coroutine.create(fn) end
function Wait() coroutine.yield() end
function GetCurrentResourceName() return 'test' end
function TriggerServerEvent(name) checked=name end
function runJobStashSpecs()
    assert(coroutine.resume(tasks[1])) assert(coroutine.resume(tasks[1]))
    local id,zone=next(zones) assert(zone and zone.options[1].label=='EMS Lockerを開く')
    assert(not zone.options[1].canInteract(),'below grade hides interaction') role.grade.level=2
    assert(zone.options[1].canInteract())
    zone.options[1].onSelect() assert(opened.kind=='stash' and opened.id=='shared_id')
    role.name='police' assert(not zone.options[1].canInteract())
    events['QBCore:Client:OnJobUpdate']() assert(checked=='ptech_omnite_toolbox:jobstash:checkAccess') role.name='ambulance'
    events['ptech_omnite_toolbox:jobstash:state'](points)
    assert(zones[id],'unchanged periodic snapshots preserve target zones')
    SeatingClient.openJobStashes() contexts.omnite_job_stashes.options[1].onSelect()
    assert(saved.name=='Shared items' and saved.job=='ambulance' and saved.minGrade==0 and saved.slots==100 and saved.maxWeight==500000 and saved.relocate,'kg values are converted to grams')
    point.enabled=false events['ptech_omnite_toolbox:jobstash:state'](points)
    assert(next(zones)==nil and not zone.options[1].canInteract(),'disabled point has no target')
    point.enabled=true events['ptech_omnite_toolbox:jobstash:state'](points) assert(next(zones))
    events['QBCore:Client:OnPlayerUnload']() assert(next(zones)==nil)
    events['ptech_omnite_toolbox:jobstash:state'](points) assert(next(zones)==nil,'late state after logout is ignored')
    events['QBCore:Client:OnPlayerLoaded']() assert(next(zones))
    events.onResourceStop('test') assert(next(zones)==nil)
end
