local mt = {}
mt.__sub = function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end
mt.__len = function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local positions = { [1]=vec3(0,0,0), [2]=vec3(0,0,0) }
local buckets = { [1]=0,[2]=0 }
local identities = { [1]='owner1',[2]='owner2' }
local tools, ems, admins = { [1]=true,[2]=true }, {}, {}
local callbacks, events, commands, exported = {}, {}, {}, {}
local ready, nextId, dbFail, duringUpdate = nil, 1, false, nil
local dbRows, sent = {}, {}
local transferAllowed,transferError,transferCount=true,false,0
local dbMlos={}
function GetPlayerPed(src) return positions[src] and src or 0 end
function GetEntityCoords(ped) return positions[ped] end
function GetPlayerRoutingBucket(src) return buckets[src] end
function GetPlayers() return {'1','2'} end
function GetGameTimer() return 100000 end
function GetResourceState() return 'started' end
function GetInvokingResource() return 'ptech_mediora_medical' end
function IsPlayerAceAllowed(src) return admins[src] == true end
function joaat() return 123 end
function RegisterNetEvent(name,handler) events[name]=handler end
function AddEventHandler(name,handler)
    local previous=events[name]
    events[name]=function(...) if previous then previous(...) end handler(...) end
end
function RegisterCommand(name,handler,restricted) commands[name]={handler,restricted} end
function CreateThread() end
function TriggerClientEvent(...) sent[#sent+1]={...} end
function TriggerEvent() end
json = {encode=function(t) return t end,decode=function(t) return t end}
lib = {callback={register=function(name,handler) callbacks[name]=handler end}}
exports = setmetatable({
    qbx_core = {GetPlayer=function(_,src) return {PlayerData={citizenid=identities[src],job={name=ems[src] and 'ambulance' or 'mechanic'}}} end},
    ptech_mediora_escort={PreparePatientBed=function(_,actor,patient)
        transferCount=transferCount+1
        assert(actor==1 and patient==2,'carry release receives validated patient IDs')
        if transferError then error('escort stopped') end
        return transferAllowed
    end},
    ox_inventory = {GetItemCount=function(_,src) return tools[src] and 1 or 0 end,AddItem=function() return true end},
}, {__call=function(_,name,handler) exported[name]=handler end})
MySQL = {
    ready=function(fn) ready=fn end,
    query={await=function(sql)
        if sql:find('SELECT * FROM ptech_omnite_seating_mlos',1,true) then return dbMlos end
        if sql:find('SELECT') then return dbRows end return {}
    end},
    insert={await=function(sql,params)
        if dbFail then error('offline') end
        local id=nextId nextId=nextId+1
        dbRows[#dbRows+1]={id=id,owner=params[1],mlo=params[2],name=params[3],kind=params[4],payload=params[5],bucket=params[6],revision=1}
        return id
    end},
    update={await=function(sql,params)
        if sql:find('INSERT INTO ptech_omnite_seating_mlos',1,true) then
            if dbFail then error('offline') end
            dbMlos[#dbMlos+1]={id=params[1],label=params[2],owner=params[3]}
            return 1
        end
        if duringUpdate then duringUpdate() end
        if dbFail then error('offline') end
        local deleting=sql:find('DELETE')
        local id,revision=deleting and params[1] or params[5],deleting and params[2] or params[6]
        for i,row in ipairs(dbRows) do
            if tostring(row.id)==tostring(id) and row.revision==revision then
                if deleting then table.remove(dbRows,i) else row.payload=params[4] row.revision=revision+1 end
                return 1
            end
        end
        return 0
    end},
}

local prefix='ptech_omnite_seating:'
local function invoke(src,action,...) return callbacks[prefix..action](src,...) end
local function input(kind)
    return {mlo='pillbox',name='waiting_01',kind=kind or 'chair',coords={x=0,y=0,z=0},heading=90,style='standard'}
end
local function tick(src) source=src events['playerDropped']() end

function runSpecs()
    local S=SeatingServer
    assert(not invoke(1,'tool').ok,'DB readiness required')
    ready()
    assert(S.ready and invoke(1,'tool').ok)
    local registered=invoke(1,'registerMlo','ピルボックス病院')
    assert(registered.ok and #invoke(1,'tool').mlos==1,'MLO names saved independently of seats')
    assert(invoke(2,'registerMlo','ピルボックス病院').id==registered.id,'duplicate MLO name reuses existing registry')
    assert(not invoke(1,'registerMlo','').ok,'empty MLO rejected')
    dbFail=true
    assert(not invoke(1,'registerMlo','未保存MLO').ok and #invoke(1,'tool').mlos==1,'failed MLO save never published')
    dbFail=false
    tools[2]=false assert(not invoke(2,'registerMlo','権限なし').ok,'MLO registry requires tool') tools[2]=true
    tools[1]=false assert(not invoke(1,'save',input()).ok,'missing tool') tools[1]=true
    assert(not invoke(1,'save',input('patient_bed')).ok,'non EMS denied') tick(1)
    local bad=input() bad.coords.x=0/0
    assert(not invoke(1,'save',bad).ok,'NaN denied') tick(1)
    bad=input() bad.coords.x=99
    assert(not invoke(1,'save',bad).ok,'distance denied') tick(1)
    dbFail=true
    assert(not invoke(1,'save',input()).ok and next(S.placed)==nil,'failed DB never published')
    dbFail=false tick(1)
    local saved=invoke(1,'save',input())
    assert(saved.ok and S.placed[saved.id].owner=='owner1')
    local id=saved.id
    tick(1)
    local linked=input('bed')
    linked.group=S.placed[id].group
    linked.coords.x=1.0
    local linkedResult=invoke(1,'save',linked)
    assert(linkedResult.ok and S.placed[linkedResult.id].group==S.placed[id].group and S.placed[linkedResult.id].kind=='bed','one furniture group supports independent sitting and lying points') tick(1)
    linked.group='unknown_group'
    assert(not invoke(1,'save',linked).ok,'unknown furniture groups rejected') tick(1)
    linked.group=S.placed[id].group
    assert(not invoke(2,'save',linked).ok,'other owners cannot append points to furniture') tick(2)
    linked.mlo='different_mlo'
    assert(not invoke(1,'save',linked).ok,'furniture group remains in one MLO') tick(1)
    local oldLimit=Config.Placement.maxPerGroup
    Config.Placement.maxPerGroup=2 linked.mlo='pillbox'
    assert(not invoke(1,'save',linked).ok,'furniture point limit enforced') tick(1)
    Config.Placement.maxPerGroup=oldLimit
    local counter=input('counter')
    counter.style='bar'
    local counterResult=invoke(1,'save',counter)
    assert(counterResult.ok and S.placed[counterResult.id].kind=='counter','counter kind and matching posture persisted') tick(1)
    counter.style='lying'
    assert(not invoke(1,'save',counter).ok,'incompatible posture rejected for counter') tick(1)
    assert(OmniteSeating.styleFor('chair','armchair').id=='standard','old armchair saves migrate to standard without losing seats')
    for _,kind in ipairs({'bed','patient_bed'}) do
        assert(#OmniteSeating.stylesFor(kind)==4,'sleeping catalog shared by preview and G menu')
        for _,id in ipairs({'lying','sleep','prone','lie_relaxed'}) do assert(OmniteSeating.styleFor(kind,id),'sleep pose accepted server-side') end
    end
    local edit=input() edit.id=id edit.revision=1
    assert(invoke(2,'save',edit).ok and S.placed[id].owner=='owner1','tool holder edits another creator seat without changing owner') tick(2)
    Config.Placement.deleteByToolHolder=false
    assert(not invoke(2,'delete',{id=id,revision=2}).ok,'shared deletion can be disabled') tick(2)
    Config.Placement.deleteByToolHolder=true
    tools[2]=false
    assert(not invoke(2,'delete',{id=id,revision=2}).ok,'shared deletion requires tool possession') tools[2]=true tick(2)
    assert(not invoke(2,'delete',{id=counterResult.id,revision=0}).ok,'shared deletion rejects stale revisions') tick(2)
    assert(invoke(2,'delete',{id=counterResult.id,revision=1}).ok and not S.placed[counterResult.id],'tool holder deletes another creator seat') tick(2)
    tools[2]=false
    assert(not invoke(2,'save',edit).ok,'shared editing still requires tool') tools[2]=true tick(2)
    Config.Placement.editByToolHolder=false
    assert(not invoke(2,'save',edit).ok,'shared editing can be disabled in config') tick(2)
    Config.Placement.editByToolHolder=true
    edit.revision=0
    assert(not invoke(1,'save',edit).ok,'stale revision rejected') tick(1)
    edit.revision=2
    assert(S.claim(1,{key='db:'..id}))
    assert(not invoke(2,'delete',{id=id,revision=2}).ok,'shared deletion rejects occupied seats') tick(2)
    assert(not S.claim(2,{key='db:'..id}),'single occupancy')
    assert(not invoke(1,'save',edit).ok,'occupied seats cannot change') tick(1)
    assert(S.claim(2,{key='db:'..id}),'disconnect releases lock') S.release(2)
    buckets[2]=1
    assert(not S.claim(2,{key='db:'..id}),'routing bucket isolation') buckets[2]=0
    duringUpdate=function() assert(not S.claim(2,{key='db:'..id}),'no sitting during DB write') end
    edit.heading=180
    edit.name="受付 'A'"
    assert(invoke(1,'save',edit).ok and S.placed[id].revision==3)
    duringUpdate=nil tick(1)
    Config.FixedSeats={{id='far',coords=vec3(500,0,0)}}
    assert(not S.claim(1,{key='fixed:far',coords={x=0,y=0,z=0}}),'fixed coordinate forgery rejected')
    assert(not S.claim(1,{key='prop:999:0.000:0.000:0.000'}),'unregistered model rejected')
    assert(not S.claim(1,{key='forged'}),'unknown keys rejected')
    assert(S.claim(1,{key='prop:123:0.000:0.000:0.000'}))
    assert(not S.claim(2,{key='db:'..id}),'overlapping keys share exclusion') S.release(1)
    assert(not invoke(1,'export').ok,'admin export only') admins[1]=true
    local output=invoke(1,'export','pillbox').text
    assert(output:find('Config.FixedSeats',1,true) and load(output),'Japanese and quoted seat names export valid Lua')
    assert(invoke(1,'registerMlo','pillbox').ok,'legacy MLO can be registered permanently')
    ems[1]=true
    local bed=invoke(1,'save',input('patient_bed'))
    assert(bed.ok and exported.GetPatientBeds()[bed.id]) tick(1)
    local deletion={id=bed.id,revision=1}
    ems[1]=false
    assert(not invoke(1,'delete',deletion).ok,'patient edit needs EMS even for admin') tick(1)
    ems[1]=true
    assert(not invoke(2,'placePatient',1,bed.id).ok,'non EMS patient transfer rejected')
    transferAllowed=false
    assert(not invoke(1,'placePatient',2,bed.id).ok,'another carrier cannot be interrupted')
    assert(not S.isOccupied('db:'..bed.id,0),'failed transfer releases bed reservation')
    transferAllowed=true transferError=true
    assert(not invoke(1,'placePatient',2,bed.id).ok,'escort export failure aborts transfer')
    assert(not S.isOccupied('db:'..bed.id,0),'export error also releases bed reservation')
    transferError=false
    assert(invoke(1,'placePatient',2,bed.id).ok,'EMS patient transfer shares seat lock')
    assert(transferCount==3,'carry release runs only after bed authorization')
    assert(not S.claim(1,{key='db:'..bed.id}),'patient transfer occupies bed')
    S.release(2)
    dbFail=true assert(not invoke(1,'delete',deletion).ok and S.placed[bed.id],'delete DB failure retains seat') dbFail=false tick(1)
    assert(invoke(1,'delete',deletion).ok and not S.placed[bed.id])
    S.placed={} S.ready=false ready()
    assert(S.placed[id] and S.placed[id].heading==180,'restart restores DB state')
    local restored=false
    for _,entry in ipairs(invoke(1,'tool').mlos) do if entry.id==registered.id and entry.label=='ピルボックス病院' then restored=true end end
    assert(restored,'empty MLO registry persists across restart')
    assert(commands.omnite_seatdebug[2] and commands.omnite_seatghost[2],'debug commands restricted server-side')
    local before=#sent
    assert(exported.usePlacementTool('usingItem',{}, {id=1}) ~= false,'tool use allowed with possession')
    assert(#sent==before,'server does not duplicate client menu')
    tools[1]=false
    assert(exported.usePlacementTool('usingItem',{}, {id=1}) == false,'inventory use rechecks possession')
    assert(#sent==before+1,'rejected inventory use gives feedback')
end

function runCsvSpecs()
    tools[1]=true admins[1]=true ems[1]=true
    local exported=invoke(1,'csv','export') assert(exported.ok)
    local headers={'id','mlo','name','kind','x','y','z','heading','style','group','bucket'}
    local rows=OmniteCsv.decode(exported.text,headers) assert(#rows>0)
    local multiline=OmniteCsv.encode({'value'},{{value='quoted, "text"\nline'}})
    assert(OmniteCsv.decode(multiline,{'value'})[1].value=='quoted, "text"\nline','parser preserves quoted newlines')
    local id=rows[1].id
    rows[1].name='日本語, "引用"'
    local committed=false
    MySQL.transaction={await=function(queries) assert(#queries>=2) return committed end}
    local text=OmniteCsv.encode(headers,{rows[1]})
    local previous=SeatingServer.placed[id].name
    assert(not invoke(1,'csv','import',text).ok and SeatingServer.placed[id].name==previous,'failed transaction leaves runtime untouched')
    committed=true
    assert(invoke(1,'csv','import',text).ok and SeatingServer.placed[id].name==rows[1].name,'CSV updates existing ID, including quoted Unicode')
    rows[1].id='99999' rows[1].group=''
    assert(invoke(1,'csv','import',OmniteCsv.encode(headers,{rows[1]})).ok and SeatingServer.placed['99999'],'CSV inserts new ID')
    local duplicate=OmniteCsv.encode(headers,{rows[1],rows[1]})
    assert(not invoke(1,'csv','import',duplicate).ok,'duplicate IDs rejected before transaction')
    local ok=pcall(OmniteCsv.decode,'id,wrong\n1,2',headers) assert(not ok,'bad header rejected')
    assert(not invoke(1,'csv','import','id,"unclosed').ok,'unclosed CSV quote rejected')
end
