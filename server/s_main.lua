--[[
    spraypaint - server logic

    The server is the only authority: it verifies items, validates the strokes
    arriving from a client and keeps the graffiti both in memory and in the
    database.
]]--

local graffiti = {}     -- [id] = record
local cooldown = {}     -- [player] = tick of the last save

local SAVE_COOLDOWN = 3000

local function notify(plr, title, text, color)
    Integration.notify(plr, title, text, color)
end

-- ─── Loading from the database ───────────────────────────────────────────────

local function loadAll()
    if not Db.init() then return end

    local rows = Db.loadAll()
    if not rows then
        outputDebugString("[spraypaint] ERROR: no database connection, graffiti will not load.", 1)
        outputServerLog("[spraypaint] ERROR: no database connection - graffiti will not load")
        return
    end

    local loaded, broken = 0, 0
    for _, row in ipairs(rows) do
        local strokes = fromJSON(row.strokes or "")
        if type(strokes) == "table" and #strokes > 0 then
            graffiti[row.id] = {
                id        = row.id,
                x = row.x, y = row.y, z = row.z,
                nx = row.nx, ny = row.ny, nz = row.nz,
                width     = row.width,
                height    = row.height,
                dimension = row.dimension or 0,
                interior  = row.interior or 0,
                strokes   = strokes,
                ownerId   = row.owner_id,
                ownerName = row.owner_name,
                rev       = 1,
            }
            loaded = loaded + 1
        else
            broken = broken + 1
        end
    end

    outputDebugString(("[spraypaint] loaded %d graffiti (%d broken records skipped)")
        :format(loaded, broken), 3)
end

addEventHandler("onResourceStart", resourceRoot, loadAll)

-- ─── Streaming to clients ────────────────────────────────────────────────────

local function packFor(g)
    return {
        id = g.id, rev = g.rev,
        x = g.x, y = g.y, z = g.z,
        nx = g.nx, ny = g.ny, nz = g.nz,
        width = g.width, height = g.height,
        dimension = g.dimension, interior = g.interior,
        strokes = g.strokes,
    }
end

local function syncTo(plr)
    if not isElement(plr) then return end
    local px, py, pz = getElementPosition(plr)

    local list = {}
    for _, g in pairs(graffiti) do
        local dx, dy, dz = g.x - px, g.y - py, g.z - pz
        if (dx*dx + dy*dy + dz*dz) <= (Config.StreamRadius * Config.StreamRadius) then
            list[#list + 1] = packFor(g)
        end
    end

    if #list > 0 then
        triggerClientEvent(plr, "spraypaint:sync", resourceRoot, list)
    end
end

addEvent("spraypaint:requestSync", true)
addEventHandler("spraypaint:requestSync", root, function()
    if not isElement(client) then return end
    syncTo(client)
end)

local function broadcast(g)
    for _, plr in ipairs(getElementsByType("player")) do
        local px, py, pz = getElementPosition(plr)
        local dx, dy, dz = g.x - px, g.y - py, g.z - pz
        if (dx*dx + dy*dy + dz*dz) <= (Config.StreamRadius * Config.StreamRadius) then
            triggerClientEvent(plr, "spraypaint:sync", resourceRoot, { packFor(g) })
        end
    end
end

-- ─── Item checks and start ───────────────────────────────────────────────────

local function hasItem(plr, item)
    if not Config.RequireItems then return true end
    local ok, n = pcall(Integration.countItem, plr, item)
    return ok and (tonumber(n) or 0) > 0
end

-- Finds the first colored spray the player owns, otherwise the plain one.
local function resolveSprayItem(plr)
    for itemName, colorIdx in pairs(Config.ColoredItems) do
        if Config.RequireItems and hasItem(plr, itemName) then
            return itemName, colorIdx
        end
    end
    if hasItem(plr, Config.SprayItem) then
        return Config.SprayItem, nil
    end
    return nil
end

local pendingItem = {}      -- [player] = item the player started spraying with

addEvent("spraypaint:request", true)
addEventHandler("spraypaint:request", root, function()
    local plr = client
    if not isElement(plr) then return end

    local item, forcedColor = resolveSprayItem(plr)
    if not item then
        return notify(plr, "Spray", "You don't have a spray can.", {255, 80, 80})
    end

    pendingItem[plr] = item
    triggerClientEvent(plr, "spraypaint:beginPaint", resourceRoot, forcedColor)
end)

addEvent("spraypaint:requestErase", true)
addEventHandler("spraypaint:requestErase", root, function()
    local plr = client
    if not isElement(plr) then return end

    if not hasItem(plr, Config.ClothItem) then
        return notify(plr, "Cloth", "You don't have a cloth.", {255, 80, 80})
    end

    triggerClientEvent(plr, "spraypaint:beginErase", resourceRoot)
end)

addEventHandler("onPlayerQuit", root, function()
    pendingItem[source] = nil
    cooldown[source] = nil
end)

-- ─── Saving a new graffiti ───────────────────────────────────────────────────

local function isFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function validateGeometry(d)
    for _, key in ipairs({"x","y","z","nx","ny","nz","width","height"}) do
        if not isFinite(tonumber(d[key])) then return false, "invalid geometry" end
    end
    if d.width  < Config.MinAreaSize or d.width  > Config.MaxAreaWidth  then return false, "invalid width" end
    if d.height < Config.MinAreaSize or d.height > Config.MaxAreaHeight then return false, "invalid height" end
    if Util.isBlacklisted(d.x, d.y, d.z) then return false, "blacklisted zone" end
    return true
end

addEvent("spraypaint:save", true)
addEventHandler("spraypaint:save", root, function(data)
    local plr = client
    if not isElement(plr) or type(data) ~= "table" then return end

    local now = getTickCount()
    if cooldown[plr] and now - cooldown[plr] < SAVE_COOLDOWN then return end
    cooldown[plr] = now

    local item = pendingItem[plr]
    if not item or not hasItem(plr, item) then
        return notify(plr, "Spray", "Your spray can is gone.", {255, 80, 80})
    end

    local okGeom, geomErr = validateGeometry(data)
    if not okGeom then
        return notify(plr, "Spray", "Cannot save: " .. geomErr, {255, 80, 80})
    end

    -- The player has to be at the canvas. Without this check you could spray
    -- across the whole map.
    local px, py, pz = getElementPosition(plr)
    if Util.dist3D(px, py, pz, data.x, data.y, data.z) > Config.MaxSaveDistance then
        return notify(plr, "Spray", "You are too far from the canvas.", {255, 80, 80})
    end

    local strokes, err = Util.validateStrokes(data.strokes)
    if not strokes then
        return notify(plr, "Spray", "Cannot save: " .. err, {255, 80, 80})
    end

    local ownerId = nil
    local okOwner, res = pcall(Integration.getOwnerId, plr)
    if okOwner then ownerId = res end

    if Config.MaxPerPlayer > 0 and ownerId then
        local mine = 0
        for _, g in pairs(graffiti) do
            if g.ownerId == ownerId then mine = mine + 1 end
        end
        if mine >= Config.MaxPerPlayer then
            return notify(plr, "Spray", "You already have the maximum number of graffiti. Wipe one off first.", {255, 150, 50})
        end
    end

    local id = Db.insert(data, ownerId, getPlayerName(plr), toJSON(strokes))

    if not id then
        outputDebugString("[spraypaint] INSERT failed - is the database reachable?", 1)
        return notify(plr, "Spray",
            Db.isReady() and "Saving to the database failed."
                          or "The database is not available.",
            {255, 80, 80})
    end

    graffiti[id] = {
        id = id,
        x = data.x, y = data.y, z = data.z,
        nx = data.nx, ny = data.ny, nz = data.nz,
        width = data.width, height = data.height,
        dimension = tonumber(data.dimension) or 0,
        interior  = tonumber(data.interior) or 0,
        strokes   = strokes,
        ownerId   = ownerId,
        ownerName = getPlayerName(plr),
        rev       = 1,
    }

    if Config.ConsumeSprayOnSave and Config.RequireItems then
        pcall(Integration.takeItem, plr, item, 1)
    end
    pendingItem[plr] = nil

    broadcast(graffiti[id])
    notify(plr, "Spray", "Graffiti done.", {80, 220, 100})

    if Config.LogCreate then
        Spray_log("create", plr, graffiti[id])
    end
end)

-- ─── Wiping with the cloth ───────────────────────────────────────────────────

addEvent("spraypaint:erase", true)
addEventHandler("spraypaint:erase", root, function(id)
    local plr = client
    if not isElement(plr) then return end

    id = tonumber(id)
    local g = id and graffiti[id]
    if not g then return end

    if not hasItem(plr, Config.ClothItem) then
        return notify(plr, "Cloth", "You don't have a cloth.", {255, 80, 80})
    end

    local px, py, pz = getElementPosition(plr)
    if Util.dist3D(px, py, pz, g.x, g.y, g.z) > Config.EraserMaxDistance + 5.0 then
        return notify(plr, "Cloth", "You are too far away.", {255, 80, 80})
    end

    Db.delete(id)
    graffiti[id] = nil
    triggerClientEvent(root, "spraypaint:removed", resourceRoot, id)

    if Config.ConsumeClothOnSave and Config.RequireItems then
        pcall(Integration.takeItem, plr, Config.ClothItem, 1)
    end

    notify(plr, "Cloth", "Graffiti wiped off.", {80, 220, 100})

    -- Hook for jobs / payouts, see s_integration.lua. Empty by default.
    pcall(Integration.onGraffitiErased, plr, g)

    if Config.LogErase then
        Spray_log("erase", plr, g)
    end
end)

-- ─── Access for the admin module ─────────────────────────────────────────────

function Spray_getAll()  return graffiti end

function Spray_delete(id)
    id = tonumber(id)
    local g = id and graffiti[id]
    if not g then return false end

    Db.delete(id)
    graffiti[id] = nil
    triggerClientEvent(root, "spraypaint:removed", resourceRoot, id)
    return true, g
end
