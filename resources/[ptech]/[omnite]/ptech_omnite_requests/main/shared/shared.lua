PTechRequests = {}

-- 出力はConfig.Boardsへ貼り付け可能なLuaテーブルにします。
function PTechRequests.ToLua(value)
    local kind=type(value)
    if kind=='string' then return string.format('%q',value) end
    if kind=='number' or kind=='boolean' then return tostring(value) end
    if kind=='vector3' then return ('vec3(%.4f,%.4f,%.4f)'):format(value.x,value.y,value.z) end
    if kind~='table' then return 'nil' end
    local parts={}
    for key,item in pairs(value) do
        if key~='revision' then parts[#parts+1]='['..PTechRequests.ToLua(key)..']='..PTechRequests.ToLua(item) end
    end
    table.sort(parts)
    return '{'..table.concat(parts,',')..'}'
end

function PTechRequests.GetBoard(boardId)
    for _, board in ipairs(Config.Boards or {}) do
        if board.id == boardId then return board end
    end
end

function PTechRequests.StatusLabel(status)
    local labels = {
        open = Config.Text.open,
        accepted = Config.Text.accepted,
        completed = Config.Text.completed,
        cancelled = Config.Text.cancelled,
    }
    return labels[status] or status
end

function PTechRequests.ModeLabel(mode)
    if mode == 'delivery' then return Config.Text.deliveryMode end
    return Config.Text.acceptedMode
end
