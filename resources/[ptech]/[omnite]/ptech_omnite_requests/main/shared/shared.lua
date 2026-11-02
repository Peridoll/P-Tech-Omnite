PTechRequests = {}

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
