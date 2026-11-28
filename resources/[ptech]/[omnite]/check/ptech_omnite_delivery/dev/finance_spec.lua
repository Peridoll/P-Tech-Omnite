local stores,runs,transfers={},{},{}
local initialize,failTransaction
json={encode=function(value) return value end}
local function execute(sql,args)
    args=args or {}
    if sql:find('CREATE TABLE',1,true) then return {} end
    if sql:find('INSERT IGNORE INTO ptech_omnite_delivery_stores',1,true) then stores[args[1]]=stores[args[1]] or {points=0,vault=0} return {} end
    if sql:find('INSERT INTO ptech_omnite_delivery_runs',1,true) then
        local a=stores[args[6]]
        if a and a.vault>=args[7] then runs[args[1]]={token=args[1],shop_id=args[6],owner=args[2],reward=args[4],points=args[5],status='active'} end
    elseif sql:find('SELECT shop_id,SUM(reward)',1,true) then
        for _,r in pairs(runs) do if r.status=='active' then stores[r.shop_id].vault=stores[r.shop_id].vault+r.reward end end
    elseif sql:find('UPDATE ptech_omnite_delivery_stores a JOIN ptech_omnite_delivery_runs',1,true) then
        local r=runs[args[1]]
        if sql:find("r.status='active'",1,true) and r and r.status=='active' then stores[r.shop_id].vault=stores[r.shop_id].vault+r.reward end
        if sql:find("r.status='paying'",1,true) and r and r.status=='paying' then stores[r.shop_id].points=stores[r.shop_id].points+r.points end
    elseif sql:find('SET vault=vault-?',1,true) then
        if runs[args[3]] then stores[args[2]].vault=stores[args[2]].vault-args[1] end
    elseif sql:find('UPDATE ptech_omnite_delivery_runs',1,true) then
        local status,old=sql:match("SET status='(%w+)'"),sql:match("AND status='(%w+)'") or sql:match("WHERE status='(%w+)'")
        if args[1] then local r=runs[args[1]] if r and r.status==old then r.status=status return 1 end return 0 end
        for _,r in pairs(runs) do if r.status==old then r.status=status end end
    elseif sql:find('UPDATE ptech_omnite_delivery_transfers',1,true) then
        for _,t in pairs(transfers) do if t.status=='prepared' then t.status='review' end end
    elseif sql:find("SELECT * FROM ptech_omnite_delivery_runs WHERE status='review'",1,true) then
        local rows={} for _,r in pairs(runs) do if r.status=='review' then rows[#rows+1]=r end end return rows
    end
    return {}
end
MySQL={ready=function(fn) initialize=fn end,
    query={await=execute},update={await=execute},
    single={await=function(_,args) return stores[args[1]] end},
    scalar={await=function(sql,args)
        if sql:find('SELECT token FROM ptech_omnite_delivery_runs',1,true) then return runs[args[1]] and args[1] end
        return 0
    end},
    transaction={await=function(queries)
        if failTransaction then return false end
        for _,entry in ipairs(queries) do execute(entry.query,entry.values) end return true
    end},
}
function runFinanceSpecs()
    initialize()
    local F=DeliveryFinance assert(F.ready)
    F.register('a') F.register('b') stores.a.vault=800000 stores.b.vault=400000
    local function mission(token,shop) return {token=token,shop=shop,owner='owner',reward=400000,points=600} end
    local a,b,c=mission('a1','a'),mission('a2','a'),mission('a3','a')
    assert(F.reserve(a) and stores.a.vault==400000)
    assert(F.reserve(b) and stores.a.vault==0)
    assert(not F.reserve(c) and not runs[c.token],'insufficient funds inserts no reservation')
    F.refund(a) F.refund(a)
    assert(stores.a.vault==400000 and runs.a1.status=='refunded','duplicate refunds return cash exactly once')
    assert(F.beginPay(b) and not F.beginPay(b),'only one payout can claim a run')
    F.complete(b) F.complete(b)
    assert(stores.a.points==600 and stores.b.points==0,'duplicate completion credits one store once')
    assert(F.reserve(c))
    local d=mission('b1','b') assert(F.reserve(d)) assert(F.beginPay(d))
    transfers.pending={status='prepared'}
    initialize()
    assert(stores.a.vault==400000 and runs.a3.status=='refunded','restart automatically returns active escrow')
    assert(stores.b.vault==0 and runs.b1.status=='review','uncertain payout is not refunded or paid twice')
    assert(transfers.pending.status=='review','uncertain cash transfer remains auditable')
    initialize()
    assert(stores.a.vault==400000 and stores.a.points==600,'second restart cannot repeat refunds or points')
    failTransaction=true
    assert(not pcall(F.reserve,mission('fail','a')) and stores.a.vault==400000,'transaction failure preserves balance')
end
