local callbackPrefix = 'ptech_omnite_requests:'
local contextPrefix = 'ptech_omnite_requests:'

local function notify(message, type)
    lib.notify({ title = Config.Text.resourceTitle, description = message, type = type or 'inform' })
end

local function requestBoard(boardId)
    local response = lib.callback.await(callbackPrefix .. 'getBoard', false, boardId)
    if not response or not response.ok then
        notify(response and response.message or Config.Text.notAvailable, 'error')
        return nil
    end
    return response
end

local function refreshBoard(boardId)
    local response = requestBoard(boardId)
    if response then showBoard(boardId, response) end
end

local function submitAction(callbackName, boardId, requestId, quantity)
    local response = lib.callback.await(callbackPrefix .. callbackName, false, boardId, requestId, quantity)
    if not response or not response.ok then
        notify(response and response.message or Config.Text.notAvailable, 'error')
        return
    end
    notify(response.message or Config.Text.missionCompleted, 'success')
    showBoard(boardId, response)
end

local function inputForField(field)
    local entry = { label = field.label, required = field.required == true }
    if field.type == 'textarea' then
        entry.type = 'textarea'
        entry.max = field.maxLength or 500
    elseif field.type == 'number' then
        entry.type = 'number'
        entry.min = field.min
        entry.max = field.max
    elseif field.type == 'select' then
        entry.type = 'select'
        entry.options = {}
        for _, option in ipairs(field.options or {}) do
            entry.options[#entry.options + 1] = { label = option.label, value = option.value }
        end
    else
        entry.type = 'input'
        entry.max = field.maxLength or 500
    end
    return entry
end

local function createRequest(boardId, board)
    local modeOptions = {
        { label = Config.Text.acceptedMode, value = 'accepted' },
        { label = Config.Text.deliveryMode, value = 'delivery' },
    }
    local baseInputs = {
        { type = 'input', label = Config.Text.requestTitle, required = true, max = Config.RequestTitleMaxLength },
        { type = 'textarea', label = Config.Text.requestDescription, required = false, max = Config.RequestDescriptionMaxLength },
        { type = 'select', label = Config.Text.mode, required = true, options = modeOptions },
    }
    local baseValues = lib.inputDialog(Config.Text.createMission, baseInputs)
    if not baseValues then return end

    local mode = baseValues[3]
    local inputs, payload = {}, {
        title = baseValues[1],
        description = baseValues[2] or '',
        mode = mode,
        fields = {},
    }
    for _, field in ipairs(board.fields or {}) do
        inputs[#inputs + 1] = inputForField(field)
    end

    if mode == 'accepted' then
        inputs[#inputs + 1] = {
            type = 'number', label = Config.Text.maxAcceptances, required = true,
            min = 1, max = board.maxAcceptances or 1, default = 1,
        }
    else
        local itemOptions = {}
        for _, item in ipairs(board.deliveryItems or {}) do
            itemOptions[#itemOptions + 1] = {
                label = ('%s（上限 %s / 個）'):format(item.label, item.maxRewardPerItem),
                value = item.name,
            }
        end
        if #itemOptions == 0 then
            notify('このボードには納品アイテムが設定されていません。', 'error')
            return
        end
        inputs[#inputs + 1] = { type = 'select', label = Config.Text.selectItem, required = true, options = itemOptions }
        inputs[#inputs + 1] = {
            type = 'number', label = Config.Text.maxQuantity, required = true,
            min = 1, max = board.maxDeliveryQuantity or 1, default = 1,
        }
        inputs[#inputs + 1] = {
            type = 'number', label = Config.Text.rewardPerItem, required = true,
            min = 0, default = 0,
        }
    end

    local extraValues = #inputs > 0 and lib.inputDialog(Config.Text.createMission, inputs) or {}
    if not extraValues then return end
    local valueIndex = 1
    for _, field in ipairs(board.fields or {}) do
        payload.fields[field.key] = extraValues[valueIndex]
        valueIndex = valueIndex + 1
    end
    if mode == 'accepted' then
        payload.maxAcceptances = extraValues[valueIndex]
    else
        payload.deliveryItem = extraValues[valueIndex]
        payload.maxQuantity = extraValues[valueIndex + 1]
        payload.rewardPerItem = extraValues[valueIndex + 2]
    end

    local response = lib.callback.await(callbackPrefix .. 'createRequest', false, boardId, payload)
    if not response or not response.ok then
        notify(response and response.message or Config.Text.notAvailable, 'error')
        return
    end
    notify(response.message or Config.Text.missionCreated, 'success')
    showBoard(boardId, response)
end

function showBoard(boardId, response)
    response = response or requestBoard(boardId)
    if not response then return end

    local board = response.board
    local permissions = response.permissions
    local parentId = contextPrefix .. 'board:' .. boardId
    local options = {}

    if permissions.canPost then
        options[#options + 1] = {
            title = Config.Text.createMission,
            icon = 'plus',
            onSelect = function() createRequest(boardId, board) end,
        }
    end

    if #response.requests == 0 then
        options[#options + 1] = { title = Config.Text.noMissions, disabled = true }
    end

    for _, request in ipairs(response.requests) do
        local requestId = tonumber(request.id)
        local missionId = parentId .. ':mission:' .. requestId
        local summary = ('%s · %s'):format(PTechRequests.ModeLabel(request.mode), PTechRequests.StatusLabel(request.status))
        if request.mode == 'accepted' then
            summary = ('%s · %s · %s/%s'):format(
                PTechRequests.ModeLabel(request.mode), PTechRequests.StatusLabel(request.status),
                request.accepted_count, request.max_acceptances
            )
        else
            summary = ('%s · %s · %s/%s · %s / 個'):format(
                PTechRequests.ModeLabel(request.mode), PTechRequests.StatusLabel(request.status),
                request.delivered_quantity, request.max_quantity, request.reward_per_item
            )
        end

        local missionOptions = {
            { title = request.title, description = request.description ~= '' and request.description or summary, disabled = true },
        }

        if request.mode == 'accepted' then
            local acceptedNames = {}
            for _, accepted in ipairs(request.acceptances or {}) do
                acceptedNames[#acceptedNames + 1] = ('%s（%s）'):format(accepted.display_name, PTechRequests.StatusLabel(accepted.status))
            end
            if #acceptedNames > 0 then
                missionOptions[#missionOptions + 1] = { title = Config.Text.acceptedCount, description = table.concat(acceptedNames, '、'), disabled = true }
            end
            if permissions.canAccept and request.status ~= 'completed' and request.status ~= 'cancelled'
                and request.accepted_count < request.max_acceptances and not request.myAcceptance then
                missionOptions[#missionOptions + 1] = {
                    title = Config.Text.acceptMission,
                    onSelect = function() submitAction('acceptRequest', boardId, requestId) end,
                }
            end
            if (request.myAcceptance == 'accepted' or permissions.canManage)
                and request.status ~= 'completed' and request.status ~= 'cancelled' then
                missionOptions[#missionOptions + 1] = {
                    title = Config.Text.completeMission,
                    onSelect = function() submitAction('completeRequest', boardId, requestId) end,
                }
            end
        else
            local remaining = math.max(0, request.max_quantity - request.delivered_quantity)
            missionOptions[#missionOptions + 1] = {
                title = Config.Text.remainingQuantity,
                description = ('%s / %s'):format(remaining, request.max_quantity),
                disabled = true,
            }
            if permissions.canDeliver and remaining > 0 and request.status == 'open' then
                missionOptions[#missionOptions + 1] = {
                    title = Config.Text.deliverItems,
                    onSelect = function()
                        local values = lib.inputDialog(Config.Text.deliverItems, {
                            { type = 'number', label = Config.Text.quantity, required = true, min = 1, max = remaining, default = 1 },
                        })
                        if values then submitAction('deliverItems', boardId, requestId, values[1]) end
                    end,
                }
            end
        end

        if permissions.canManage or request.created_by == permissions.citizenid then
            if request.status == 'open' or request.status == 'accepted' then
                missionOptions[#missionOptions + 1] = {
                    title = Config.Text.cancelMission,
                    icon = 'xmark',
                    onSelect = function() submitAction('cancelRequest', boardId, requestId) end,
                }
            end
        end

        lib.registerContext({ id = missionId, title = request.title, menu = parentId, options = missionOptions })
        options[#options + 1] = {
            title = request.title,
            description = summary,
            metadata = request.description ~= '' and { { label = Config.Text.requestDescription, value = request.description } } or nil,
            onSelect = function() lib.showContext(missionId) end,
        }
    end

    options[#options + 1] = { title = Config.Text.refresh, icon = 'arrows-rotate', onSelect = function() refreshBoard(boardId) end }
    lib.registerContext({ id = parentId, title = board.label, options = options })
    lib.showContext(parentId)
end

CreateThread(function()
    for _, board in ipairs(Config.Boards or {}) do
        if board.id and board.coords and board.size then
            exports.ox_target:addBoxZone({
                coords = board.coords,
                size = board.size,
                rotation = board.rotation or 0.0,
                debug = false,
                options = {
                    {
                        name = ('ptech_omnite_requests_%s'):format(board.id),
                        icon = 'fa-solid fa-clipboard-list',
                        label = board.label or Config.Text.resourceTitle,
                        distance = Config.InteractionDistance,
                        onSelect = function() showBoard(board.id) end,
                    },
                },
            })
        end
    end
end)
