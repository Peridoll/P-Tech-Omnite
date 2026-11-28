local contexts,dialogs,notifications={},{},{}
local targetThread,targetEntries,opened
local playerJob={name="diner",isboss=false}
local vaultSaved
local saved
local productSaved
local product={slot=7,key="water|metadata",name="water",label="Water",count=3,price=0,enabled=false}
local point={id='shop1',name='Shop',revision=3,model=false,finite=true,
    purchaseJobs={'diner','police'},stockJobs={'diner'},purchaseGrades={diner=1,police=2},
    coords={x=10,y=20,z=30},heading=90}
local jobs={diner={label='Diner',grades={[0]={name='New'},[1]={name='Staff'},[2]={name='Boss'}}},
    police={label='Police',grades={[0]={name='Cadet'},[2]={name='Officer'},[4]={name='Chief'}}}}
local shops={shop1=point}
SeatingClient={}
json={encode=tostring}
lib={callback={await=function(action,_,input,detail)
    if action=='ptech_omnite_shops:list' then return {ok=true,shops=shops,manager=true,jobs=jobs} end
    if action=='ptech_omnite_shops:products' then return {ok=true,products={product},revision=point.revision} end
    if action=='ptech_omnite_shops:open' then return {ok=true,shop='test_shop'} end
    if action=='ptech_omnite_shops:inventory' then return {ok=true,inventory='test_'..detail} end
    if action=='ptech_omnite_shops:vaultAccess' then vaultSaved=detail point.vaultAccess={jobs=detail.jobs,grades=detail.grades,bossOnly=detail.bossOnly} return {ok=true} end
    if action=='ptech_omnite_shops:product' then
        productSaved=detail
        product.price=detail.price product.enabled=detail.enabled point.revision=point.revision+1
        return {ok=true}
    end
    assert(action=='ptech_omnite_shops:save') saved=input return {ok=true}
end},notify=function(data) notifications[#notifications+1]=data.description end,
registerContext=function(data) contexts[data.id]=data end,showContext=function() end,
inputDialog=function(title,rows)
    dialogs[#dialogs+1]={title=title,rows=rows}
    if title=='金庫の利用権限' then return {false,{'police'},false} end
    if title=='JOB別の金庫利用階級' then return {'2'} end
    if title=='Water' then return {true,25000} end
    if title=='ショップを編集' then return {'Shop',false,'',true,false,{}, {'diner'},true} end
    return {'2','4'}
end}
function RegisterNetEvent() end
function CreateThread(fn) if not targetThread then targetThread=coroutine.create(fn) end end
function Wait() coroutine.yield() end
function PlayerPedId() return 1 end
local vectorMt={__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z}, {__len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}) end}
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},vectorMt) end
function GetEntityCoords() return vec3(10,20,31) end
function GetEntityHeading() return 90 end
exports={qbx_core={GetPlayerData=function() return {job=playerJob} end},
    ox_inventory={openInventory=function(_,kind,data) opened={kind=kind,data=data} end},
    ox_target={addBoxZone=function(_,data) targetEntries=data.options return 1 end}}

function AddEventHandler() end
local function option(context,title)
    for _,entry in ipairs(contexts[context].options) do if entry.title==title then return entry end end
    error('Missing menu item: '..title)
end
function runShopClientSpecs()
    SeatingClient.openShops()
    option('omnite_shops_manager','Shop').onSelect()
    option('omnite_shop_edit','JOB別の販売可能階級').onSelect()
    assert(#dialogs==1 and dialogs[1].title=='JOB別の販売可能階級','grade dialog opens directly')
    assert(dialogs[1].rows[1].default=='1' and dialogs[1].rows[2].default=='2','saved job grades are selected')
    assert(saved.purchaseGrades.diner==2 and saved.purchaseGrades.police==4,'each job grade is saved')
    assert(saved.relocate==false and saved.coords==point.coords and saved.heading==90,'grade edit preserves placement')
    assert(saved.stockJobs[1]=='diner' and saved.model==false and saved.finite,'grade edit preserves shop settings')
    option('omnite_shop_edit','商品リスト・販売価格').onSelect()
    option('omnite_shop_products','Water').onSelect()
    assert(productSaved.slot==7 and productSaved.key=='water|metadata' and productSaved.price==25000 and productSaved.enabled,'product dialog saves selected item and price')
    assert(option('omnite_shop_products','Water').description:find('$25000',1,true),'product list refreshes the saved price')
    local previousDialogs=#dialogs
    point.purchaseJobs={}
    SeatingClient.openShops()
    option('omnite_shops_manager','Shop').onSelect()
    option('omnite_shop_edit','JOB別の販売可能階級').onSelect()
    assert(#dialogs==previousDialogs,'unrestricted shop requires selecting purchase jobs first')
    assert(notifications[#notifications]:find('購入JOB制限',1,true),'missing jobs produce guidance')
    assert(coroutine.resume(targetThread)) assert(coroutine.resume(targetThread))
    assert(#targetEntries==3,'target has purchase, stock and boss proceeds actions')
    targetEntries[1].onSelect()
    assert(opened.kind=='shop' and opened.data.type=='test_shop','target opens purchase inventory directly')
    assert(not contexts.omnite_shop_access,'target no longer opens a management menu')
    assert(targetEntries[2].canInteract(),'finite stock can be replenished')
    targetEntries[2].onSelect()
    assert(opened.kind=='stash' and opened.data=='test_stock','stock target opens replenishment inventory')
    point.finite=false
    assert(not targetEntries[2].canInteract(),'unlimited shop has no replenishment action')
    assert(not targetEntries[3].canInteract(),'employees cannot collect proceeds')
    playerJob.isboss=true
    assert(targetEntries[3].canInteract(),'registered stock boss retains proceeds access')
    assert(targetEntries[3].label=='金庫を開く','vault target is explicitly named')
    option('omnite_shop_edit','金庫を開く権限を設定').onSelect()
    assert(vaultSaved.jobs[1]=='police' and vaultSaved.grades.police==2 and not vaultSaved.bossOnly,'toolbox saves custom vault jobs and grades')
    assert(not targetEntries[3].canInteract(),'old stock boss excluded by custom vault ACL')
    playerJob={name='police',grade={level=1},isboss=false}
    assert(not targetEntries[3].canInteract(),'vault target hidden below minimum')
    playerJob.grade.level=2
    assert(targetEntries[3].canInteract(),'vault target visible for configured nonboss grade')
    targetEntries[3].onSelect()
    assert(opened.kind=='stash' and opened.data=='test_sales','vault opens existing proceeds inventory')
    option('omnite_shop_edit','ショップ設定・NPCモデル・位置を編集').onSelect()
    assert(saved.relocate and saved.coordinateMode=='origin' and saved.coords.z==31 and saved.heading==90,'relocation records the full player origin without subtracting height')
end
