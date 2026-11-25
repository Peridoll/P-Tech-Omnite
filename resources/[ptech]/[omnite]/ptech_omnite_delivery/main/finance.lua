DeliveryFinance={ready=false}
local F=DeliveryFinance
local function q(sql,args) return {query=sql,values=args or {}} end
local function tx(queries) assert(MySQL.transaction.await(queries),'Delivery finance transaction failed') end
function F.account(id)
    return MySQL.single.await('SELECT points,vault FROM ptech_omnite_delivery_stores WHERE id=?',{id}) or {points=0,vault=0}
end
function F.register(id) MySQL.query.await('INSERT IGNORE INTO ptech_omnite_delivery_stores (id) VALUES (?)',{id}) end
function F.reserve(m)
    tx({
        q([[INSERT INTO ptech_omnite_delivery_runs (token,shop_id,owner,payload,reward,points,status)
            SELECT ?,id,?,?,?,?,'active' FROM ptech_omnite_delivery_stores WHERE id=? AND vault>=?]],
            {m.token,m.owner,json.encode(m),m.reward,m.points,m.shop,m.reward}),
        q([[UPDATE ptech_omnite_delivery_stores SET vault=vault-? WHERE id=? AND EXISTS
            (SELECT 1 FROM ptech_omnite_delivery_runs WHERE token=?)]],{m.reward,m.shop,m.token}),
    })
    return MySQL.scalar.await('SELECT token FROM ptech_omnite_delivery_runs WHERE token=?',{m.token})~=nil
end
function F.refund(m)
    tx({
        q([[UPDATE ptech_omnite_delivery_stores a JOIN ptech_omnite_delivery_runs r ON a.id=r.shop_id
            SET a.vault=a.vault+r.reward WHERE r.token=? AND r.status='active']],{m.token}),
        q("UPDATE ptech_omnite_delivery_runs SET status='refunded' WHERE token=? AND status='active'",{m.token}),
    })
end
function F.hasRun(owner)
    return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM ptech_omnite_delivery_runs WHERE owner=? AND status IN ('active','paying','review')",{owner}))>0
end
function F.used(id)
    return tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM ptech_omnite_delivery_runs WHERE
        (shop_id=? OR JSON_UNQUOTE(JSON_EXTRACT(payload,'$.pickup'))=?) AND status IN ('active','paying','review')]],{id,id}))>0
end
function F.beginPay(m)
    return MySQL.update.await("UPDATE ptech_omnite_delivery_runs SET status='paying' WHERE token=? AND status='active'",{m.token})==1
end
function F.payFailed(m)
    MySQL.query.await("UPDATE ptech_omnite_delivery_runs SET status='active' WHERE token=? AND status='paying'",{m.token})
end
function F.complete(m)
    tx({
        q([[UPDATE ptech_omnite_delivery_stores a JOIN ptech_omnite_delivery_runs r ON a.id=r.shop_id
            SET a.points=a.points+r.points WHERE r.token=? AND r.status='paying']],{m.token}),
        q("UPDATE ptech_omnite_delivery_runs SET status='paid' WHERE token=? AND status='paying'",{m.token}),
    })
end
function F.buy(id,cost)
    return MySQL.update.await('UPDATE ptech_omnite_delivery_stores SET points=points-? WHERE id=? AND points>=?',{cost,id,cost})==1
end
function F.refundPoints(id,cost) MySQL.query.await('UPDATE ptech_omnite_delivery_stores SET points=points+? WHERE id=?',{cost,id}) end
function F.wallet(src,point,action,amount)
    local inv=exports.ox_inventory
    local p=exports.qbx_core:GetPlayer(src)
    local token=MySQL.scalar.await('SELECT UUID()')
    if action=='deposit' then
        if (inv:GetItemCount(src,'money') or 0)<amount then return false,'現金が足りません。' end
        MySQL.query.await("INSERT INTO ptech_omnite_delivery_transfers (token,shop_id,owner,amount,direction,status) VALUES (?,?,?,?,?,'prepared')",{token,point.id,p.PlayerData.citizenid,amount,action})
        if not inv:RemoveItem(src,'money',amount) then
            MySQL.query.await("UPDATE ptech_omnite_delivery_transfers SET status='cancelled' WHERE token=?",{token})
            return false,'現金を入金できませんでした。'
        end
        tx({q('UPDATE ptech_omnite_delivery_stores SET vault=vault+? WHERE id=?',{amount,point.id}),q("UPDATE ptech_omnite_delivery_transfers SET status='done' WHERE token=?",{token})})
    else
        tx({q([[INSERT INTO ptech_omnite_delivery_transfers (token,shop_id,owner,amount,direction,status)
            SELECT ?,id,?,?,'withdraw','prepared' FROM ptech_omnite_delivery_stores WHERE id=? AND vault>=?]],{token,p.PlayerData.citizenid,amount,point.id,amount}),
            q([[UPDATE ptech_omnite_delivery_stores SET vault=vault-? WHERE id=? AND EXISTS
                (SELECT 1 FROM ptech_omnite_delivery_transfers WHERE token=?)]],{amount,point.id,token})})
        if not MySQL.scalar.await('SELECT token FROM ptech_omnite_delivery_transfers WHERE token=?',{token}) then return false,'金庫残高が不足しています。' end
        if not inv:AddItem(src,'money',amount) then
            tx({q('UPDATE ptech_omnite_delivery_stores SET vault=vault+? WHERE id=?',{amount,point.id}),q("UPDATE ptech_omnite_delivery_transfers SET status='cancelled' WHERE token=?",{token})})
            return false,'現金を持てません。'
        end
        MySQL.query.await("UPDATE ptech_omnite_delivery_transfers SET status='done' WHERE token=?",{token})
    end
    return true
end
function F.reviews() return {
    runs=MySQL.query.await("SELECT * FROM ptech_omnite_delivery_runs WHERE status='review'"),
    transfers=MySQL.query.await("SELECT * FROM ptech_omnite_delivery_transfers WHERE status='review'"),
} end
function F.resolve(kind,token,decision)
    if kind=='run' and (decision=='paid' or decision=='refund') then
        tx({q([[UPDATE ptech_omnite_delivery_stores a JOIN ptech_omnite_delivery_runs r ON a.id=r.shop_id
            SET a.vault=a.vault+IF(?='refund',r.reward,0),a.points=a.points+IF(?='paid',r.points,0)
            WHERE r.token=? AND r.status='review']],{decision,decision,token}),
            q("UPDATE ptech_omnite_delivery_runs SET status=? WHERE token=? AND status='review'",{decision=='paid' and 'paid' or 'refunded',token})})
    elseif kind=='transfer' and (decision=='moved' or decision=='unmoved') then
        tx({q([[UPDATE ptech_omnite_delivery_stores a JOIN ptech_omnite_delivery_transfers t ON a.id=t.shop_id
            SET a.vault=a.vault+IF((t.direction='deposit' AND ?='moved') OR (t.direction='withdraw' AND ?='unmoved'),t.amount,0)
            WHERE t.token=? AND t.status='review']],{decision,decision,token}),
            q("UPDATE ptech_omnite_delivery_transfers SET status='resolved' WHERE token=? AND status='review'",{token})})
    else error('Invalid review decision') end
end
MySQL.ready(function()
    local ok,err=pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_stores (
            id VARCHAR(48) PRIMARY KEY,points BIGINT UNSIGNED NOT NULL DEFAULT 0,vault BIGINT UNSIGNED NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_runs (
            token VARCHAR(48) PRIMARY KEY,shop_id VARCHAR(48) NOT NULL,owner VARCHAR(64) NOT NULL,payload LONGTEXT NOT NULL,
            reward BIGINT UNSIGNED NOT NULL,points INT UNSIGNED NOT NULL,status VARCHAR(24) NOT NULL,
            INDEX idx_owner_status(owner,status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS ptech_omnite_delivery_transfers (
            token VARCHAR(48) PRIMARY KEY,shop_id VARCHAR(48) NOT NULL,owner VARCHAR(64) NOT NULL,
            amount BIGINT UNSIGNED NOT NULL,direction VARCHAR(12) NOT NULL,status VARCHAR(24) NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        tx({
            q([[UPDATE ptech_omnite_delivery_stores a JOIN
                (SELECT shop_id,SUM(reward) amount FROM ptech_omnite_delivery_runs WHERE status='active' GROUP BY shop_id) r
                ON a.id=r.shop_id SET a.vault=a.vault+r.amount]]),
            q("UPDATE ptech_omnite_delivery_runs SET status='refunded' WHERE status='active'"),
            q("UPDATE ptech_omnite_delivery_runs SET status='review' WHERE status='paying'"),
            q("UPDATE ptech_omnite_delivery_transfers SET status='review' WHERE status='prepared'"),
        })
        F.ready=true
    end)
    if not ok then print('[Omnite delivery] Finance initialization failed: '..tostring(err)) end
end)
