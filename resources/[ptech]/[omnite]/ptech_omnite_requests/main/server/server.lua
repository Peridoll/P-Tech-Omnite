local callbackPrefix = 'ptech_omnite_requests:'
local requestsTable = 'ptech_omnite_requests'
local acceptancesTable = 'ptech_omnite_requests_acceptances'
local dbReady = false

local function playerData(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData
end

local function displayName(data)
    local info = data.charinfo or {}
    local name = (('%s %s'):format(info.firstname or '', info.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or data.citizenid
end

local function ruleMatches(source, rule)
    if type(rule) ~= 'table' then return false end
    if rule.public then return true end

    local data = playerData(source)
    if not data then return false end

    for _, citizenid in ipairs(rule.citizenids or {}) do
        if data.citizenid == citizenid then return true end
    end

    local function matchesGroup(groups, groupData, checkDuty)
        if not groupData then return false end
        for name, requirement in pairs(groups or {}) do
            if groupData.name == name then
                local settings = type(requirement) == 'table' and requirement or { minGrade = requirement }
                local grade = tonumber(groupData.grade and groupData.grade.level) or 0
                if grade >= (tonumber(settings.minGrade) or 0)
                    and (not (checkDuty and settings.onDuty) or groupData.onduty) then
                    return true
                end
            end
        end
        return false
    end

    return matchesGroup(rule.jobs, data.job, true) or matchesGroup(rule.gangs, data.gang, false)
end

local function can(source, board, action)
    return ruleMatches(source, board.permissions and board.permissions[action])
end

local function canView(source, board)
    return can(source, board, 'view') or can(source, board, 'post') or can(source, board, 'accept')
        or can(source, board, 'deliver') or can(source, board, 'manage')
end

local function nearBoard(source, board)
    if not board.coords then return false end
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    local size = board.size or vec3(1.0, 1.0, 1.0)
    local radius = math.sqrt((size.x / 2) ^ 2 + (size.y / 2) ^ 2 + (size.z / 2) ^ 2)
    return #(GetEntityCoords(ped) - board.coords) <= radius + Config.InteractionDistance + 0.5
end

local function errorResponse(message)
    return { ok = false, message = message }
end

local function readyAndAuthorized(source, boardId, action)
    if not dbReady then return nil, errorResponse(Config.Text.databaseNotReady) end
    local board = PTechRequests.GetBoard(boardId)
    if not board then return nil, errorResponse(Config.Text.boardNotFound) end
    if not nearBoard(source, board) then return nil, errorResponse(Config.Text.tooFar) end
    if action and not can(source, board, action) then return nil, errorResponse(Config.Text.permissionDenied) end
    return board
end

local function integerInRange(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number % 1 ~= 0 or number < minimum or number > maximum then return nil end
    return number
end

local function stringLength(value)
    return utf8.len(value) or #value
end

local function normalizeFields(board, submitted)
    if type(submitted) ~= 'table' then return nil end
    local normalized = {}
    for _, field in ipairs(board.fields or {}) do
        local value = submitted[field.key]
        if value == nil or value == '' then
            if field.required then return nil end
        elseif field.type == 'number' then
            local number = tonumber(value)
            if not number or (field.min and number < field.min) or (field.max and number > field.max) then return nil end
            normalized[field.key] = number
        elseif field.type == 'select' then
            local valid = false
            for _, option in ipairs(field.options or {}) do
                if option.value == value then valid = true break end
            end
            if not valid then return nil end
            normalized[field.key] = value
        else
            local text = tostring(value)
            if stringLength(text) > (tonumber(field.maxLength) or 500) then return nil end
            normalized[field.key] = text
        end
    end
    return normalized
end

local function encodeRequest(row)
    row.fields = json.decode(row.fields or '{}') or {}
    row.max_acceptances = tonumber(row.max_acceptances) or 0
    row.accepted_count = tonumber(row.accepted_count) or 0
    row.max_quantity = tonumber(row.max_quantity) or 0
    row.delivered_quantity = tonumber(row.delivered_quantity) or 0
    row.reward_per_item = tonumber(row.reward_per_item) or 0
    return row
end

local function getBoardData(source, boardId)
    local board, failure = readyAndAuthorized(source, boardId)
    if not board then return failure end
    if not canView(source, board) then return errorResponse(Config.Text.permissionDenied) end

    local rows = MySQL.query.await(([[
        SELECT id, board_id, board_type, mode, status, title, description, fields,
               created_by, created_name, max_acceptances, accepted_count,
               delivery_item, delivery_label, max_quantity, delivered_quantity,
               reward_per_item, created_at
        FROM `%s` WHERE board_id = ? ORDER BY id DESC LIMIT ?
    ]]):format(requestsTable), { board.id, Config.RequestListLimit }) or {}

    local data = playerData(source)
    for _, row in ipairs(rows) do
        encodeRequest(row)
        row.acceptances = MySQL.query.await(([[
            SELECT citizenid, display_name, status FROM `%s`
            WHERE request_id = ? ORDER BY accepted_at ASC
        ]]):format(acceptancesTable), { row.id }) or {}
        row.myAcceptance = nil
        for _, acceptance in ipairs(row.acceptances) do
            if data and acceptance.citizenid == data.citizenid then
                row.myAcceptance = acceptance.status
            end
            acceptance.citizenid = nil
        end
    end

    return {
        ok = true,
        board = {
            id = board.id,
            label = board.label,
            type = board.type,
            fields = board.fields or {},
            deliveryItems = board.deliveryItems or {},
            maxAcceptances = board.maxAcceptances or 1,
            maxDeliveryQuantity = board.maxDeliveryQuantity or 1,
        },
        requests = rows,
        permissions = {
            citizenid = data and data.citizenid,
            canPost = can(source, board, 'post'),
            canAccept = can(source, board, 'accept'),
            canDeliver = can(source, board, 'deliver'),
            canManage = can(source, board, 'manage'),
        },
        text = Config.Text,
    }
end

lib.callback.register(callbackPrefix .. 'getBoard', function(source, boardId)
    return getBoardData(source, boardId)
end)

lib.callback.register(callbackPrefix .. 'createRequest', function(source, boardId, payload)
    local board, failure = readyAndAuthorized(source, boardId, 'post')
    if not board then return failure end
    if type(payload) ~= 'table' then return errorResponse(Config.Text.invalidInput) end
    local data = playerData(source)
    if not data then return errorResponse(Config.Text.playerInfoUnavailable) end

    local title = type(payload.title) == 'string' and payload.title:gsub('^%s*(.-)%s*$', '%1') or ''
    if title == '' or stringLength(title) > Config.RequestTitleMaxLength then return errorResponse(Config.Text.invalidInput) end
    local description = type(payload.description) == 'string' and payload.description or ''
    if stringLength(description) > Config.RequestDescriptionMaxLength then return errorResponse(Config.Text.invalidInput) end
    local fields = normalizeFields(board, payload.fields or {})
    if not fields then return errorResponse(Config.Text.invalidInput) end

    local mode = payload.mode
    if mode ~= 'accepted' and mode ~= 'delivery' then return errorResponse(Config.Text.invalidInput) end

    local maxAcceptances, deliveryItem, deliveryLabel, maxQuantity, rewardPerItem = 0, nil, nil, 0, 0
    if mode == 'accepted' then
        maxAcceptances = integerInRange(payload.maxAcceptances, 1, tonumber(board.maxAcceptances) or 1)
        if not maxAcceptances then return errorResponse(Config.Text.invalidInput) end
    else
        local allowedItem
        for _, item in ipairs(board.deliveryItems or {}) do
            if item.name == payload.deliveryItem then allowedItem = item break end
        end
        maxQuantity = integerInRange(payload.maxQuantity, 1, tonumber(board.maxDeliveryQuantity) or 1)
        if not allowedItem or not maxQuantity then return errorResponse(Config.Text.invalidInput) end
        deliveryItem, deliveryLabel = allowedItem.name, allowedItem.label
        rewardPerItem = integerInRange(payload.rewardPerItem, 0, tonumber(allowedItem.maxRewardPerItem) or 0)
        if rewardPerItem == nil then return errorResponse(Config.Text.invalidInput) end
    end

    MySQL.insert.await(([[
        INSERT INTO `%s` (board_id, board_type, mode, status, title, description, fields,
            created_by, created_name, max_acceptances, delivery_item, delivery_label,
            max_quantity, reward_per_item)
        VALUES (?, ?, ?, 'open', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]):format(requestsTable), {
        board.id, board.type, mode, title, description, json.encode(fields),
        data.citizenid, displayName(data), maxAcceptances, deliveryItem, deliveryLabel,
        maxQuantity, rewardPerItem,
    })

    local response = getBoardData(source, boardId)
    response.message = Config.Text.missionCreated
    return response
end)

lib.callback.register(callbackPrefix .. 'acceptRequest', function(source, boardId, requestId)
    local board, failure = readyAndAuthorized(source, boardId, 'accept')
    if not board then return failure end
    local data = playerData(source)
    if not data then return errorResponse(Config.Text.playerInfoUnavailable) end

    local updated = MySQL.update.await(([[
        UPDATE `%s` SET status = IF(accepted_count + 1 >= max_acceptances, 'accepted', 'open'),
            accepted_count = accepted_count + 1
        WHERE id = ? AND board_id = ? AND mode = 'accepted'
          AND status IN ('open', 'accepted') AND accepted_count < max_acceptances
    ]]):format(requestsTable), { tonumber(requestId), board.id })
    if not updated or updated < 1 then return errorResponse(Config.Text.notAvailable) end

    local ok = pcall(function()
        MySQL.insert.await(([[
            INSERT INTO `%s` (request_id, citizenid, display_name, status)
            VALUES (?, ?, ?, 'accepted')
        ]]):format(acceptancesTable), { tonumber(requestId), data.citizenid, displayName(data) })
    end)
    if not ok then
        MySQL.update.await(([[
            UPDATE `%s` SET status = IF(accepted_count - 1 >= max_acceptances, 'accepted', 'open'),
                accepted_count = GREATEST(accepted_count - 1, 0)
            WHERE id = ? AND board_id = ? AND status != 'cancelled'
        ]]):format(requestsTable), { tonumber(requestId), board.id })
        return errorResponse(Config.Text.notAvailable)
    end

    local response = getBoardData(source, boardId)
    response.message = Config.Text.missionAccepted
    return response
end)

lib.callback.register(callbackPrefix .. 'completeRequest', function(source, boardId, requestId)
    local board, failure = readyAndAuthorized(source, boardId)
    if not board then return failure end
    local data = playerData(source)
    if not data then return errorResponse(Config.Text.playerInfoUnavailable) end
    local request = MySQL.single.await(([[
        SELECT id, mode, status FROM `%s` WHERE id = ? AND board_id = ?
    ]]):format(requestsTable), { tonumber(requestId), board.id })
    if not request or request.mode ~= 'accepted' or request.status == 'completed' or request.status == 'cancelled' then
        return errorResponse(Config.Text.notAvailable)
    end
    if not can(source, board, 'manage') then
        local accepted = MySQL.scalar.await(([[
            SELECT id FROM `%s` WHERE request_id = ? AND citizenid = ? AND status = 'accepted'
        ]]):format(acceptancesTable), { tonumber(requestId), data.citizenid })
        if not accepted then return errorResponse(Config.Text.permissionDenied) end
    end

    if can(source, board, 'manage') then
        MySQL.update.await(([[
            UPDATE `%s` SET status = 'completed' WHERE request_id = ? AND status = 'accepted'
        ]]):format(acceptancesTable), { tonumber(requestId) })
    else
        MySQL.update.await(([[
            UPDATE `%s` SET status = 'completed' WHERE request_id = ? AND citizenid = ? AND status = 'accepted'
        ]]):format(acceptancesTable), { tonumber(requestId), data.citizenid })
    end

    local completed = tonumber(MySQL.scalar.await(([[
        SELECT COUNT(*) FROM `%s` WHERE request_id = ? AND status = 'completed'
    ]]):format(acceptancesTable), { tonumber(requestId) })) or 0
    MySQL.update.await(([[
        UPDATE `%s` SET status = 'completed'
        WHERE id = ? AND board_id = ? AND status = 'accepted'
          AND accepted_count >= max_acceptances AND ? >= accepted_count
    ]]):format(requestsTable), { tonumber(requestId), board.id, completed })

    local response = getBoardData(source, boardId)
    response.message = Config.Text.missionCompleted
    return response
end)

lib.callback.register(callbackPrefix .. 'deliverItems', function(source, boardId, requestId, quantity)
    local board, failure = readyAndAuthorized(source, boardId, 'deliver')
    if not board then return failure end
    local data = playerData(source)
    if not data then return errorResponse(Config.Text.playerInfoUnavailable) end
    quantity = integerInRange(quantity, 1, tonumber(board.maxDeliveryQuantity) or 1)
    if not quantity then return errorResponse(Config.Text.invalidInput) end

    local request = MySQL.single.await(([[
        SELECT id, mode, status, delivery_item, max_quantity, delivered_quantity, reward_per_item
        FROM `%s` WHERE id = ? AND board_id = ?
    ]]):format(requestsTable), { tonumber(requestId), board.id })
    if not request or request.mode ~= 'delivery' or request.status ~= 'open' then
        return errorResponse(Config.Text.notAvailable)
    end

    local remaining = (tonumber(request.max_quantity) or 0) - (tonumber(request.delivered_quantity) or 0)
    if quantity > remaining then return errorResponse(Config.Text.invalidInput) end
    local itemCount = exports.ox_inventory:Search(source, 'count', request.delivery_item) or 0
    if itemCount < quantity then return errorResponse(Config.Text.notEnoughItems) end
    if not exports.ox_inventory:RemoveItem(source, request.delivery_item, quantity) then
        return errorResponse(Config.Text.notEnoughItems)
    end

    local payout = quantity * (tonumber(request.reward_per_item) or 0)
    local updated = MySQL.update.await(([[
        UPDATE `%s` SET status = IF(delivered_quantity + ? >= max_quantity, 'completed', 'open'),
            delivered_quantity = delivered_quantity + ?
        WHERE id = ? AND board_id = ? AND mode = 'delivery' AND status = 'open'
          AND delivered_quantity + ? <= max_quantity
    ]]):format(requestsTable), { quantity, quantity, request.id, board.id, quantity })
    if not updated or updated < 1 then
        exports.ox_inventory:AddItem(source, request.delivery_item, quantity)
        return errorResponse(Config.Text.notAvailable)
    end

    local paid = payout == 0 or exports.qbx_core:AddMoney(source, board.deliveryPaymentType or 'cash', payout, 'ptech_omnite_requests')
    if not paid then
        MySQL.update.await(([[
            UPDATE `%s` SET delivered_quantity = GREATEST(delivered_quantity - ?, 0), status = 'open'
            WHERE id = ? AND board_id = ? AND delivered_quantity >= ?
        ]]):format(requestsTable), { quantity, request.id, board.id, quantity })
        exports.ox_inventory:AddItem(source, request.delivery_item, quantity)
        return errorResponse(Config.Text.notAvailable)
    end

    local response = getBoardData(source, boardId)
    response.message = ('%s (%s x %s)'):format(Config.Text.itemsDelivered, quantity, payout)
    return response
end)

lib.callback.register(callbackPrefix .. 'cancelRequest', function(source, boardId, requestId)
    local board, failure = readyAndAuthorized(source, boardId)
    if not board then return failure end
    local data = playerData(source)
    if not data then return errorResponse(Config.Text.playerInfoUnavailable) end

    local cancelled = MySQL.update.await(([[
        UPDATE `%s` SET status = 'cancelled'
        WHERE id = ? AND board_id = ? AND status IN ('open', 'accepted')
          AND (created_by = ? OR ? = 1)
    ]]):format(requestsTable), {
        tonumber(requestId), board.id, data.citizenid, can(source, board, 'manage') and 1 or 0,
    })
    if not cancelled or cancelled < 1 then return errorResponse(Config.Text.notAvailable) end

    local response = getBoardData(source, boardId)
    response.message = Config.Text.missionCancelled
    return response
end)

CreateThread(function()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `board_id` VARCHAR(64) NOT NULL,
            `board_type` VARCHAR(16) NOT NULL,
            `mode` VARCHAR(16) NOT NULL,
            `status` VARCHAR(16) NOT NULL DEFAULT 'open',
            `title` VARCHAR(80) NOT NULL,
            `description` VARCHAR(500) NOT NULL DEFAULT '',
            `fields` LONGTEXT NOT NULL,
            `created_by` VARCHAR(64) NOT NULL,
            `created_name` VARCHAR(100) NOT NULL,
            `max_acceptances` INT UNSIGNED NOT NULL DEFAULT 0,
            `accepted_count` INT UNSIGNED NOT NULL DEFAULT 0,
            `delivery_item` VARCHAR(100) NULL,
            `delivery_label` VARCHAR(100) NULL,
            `max_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
            `delivered_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
            `reward_per_item` BIGINT UNSIGNED NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_board_status` (`board_id`, `status`),
            KEY `idx_created_by` (`created_by`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(requestsTable))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `request_id` BIGINT UNSIGNED NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `display_name` VARCHAR(100) NOT NULL,
            `status` VARCHAR(16) NOT NULL DEFAULT 'accepted',
            `accepted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `completed_at` TIMESTAMP NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_request_citizen` (`request_id`, `citizenid`),
            KEY `idx_acceptance_citizen` (`citizenid`),
            CONSTRAINT `fk_omnite_requests_acceptance`
                FOREIGN KEY (`request_id`) REFERENCES `%s` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(acceptancesTable, requestsTable))
    dbReady = true
end)
