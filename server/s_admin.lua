--[[
    spraypaint - admin tools and logging
]]--

local function isAdmin(plr)
    local ok, res = pcall(Integration.isAdmin, plr)
    return ok and res and true or false
end

local function notify(plr, text, color)
    Integration.notify(plr, "Graffiti", text, color or {120, 220, 255})
end

-- ─── Logging ─────────────────────────────────────────────────────────────────
-- Always written to the server log; additionally posted to Discord when
-- Config.DiscordWebhook is filled in. A plain fetchRemote POST, so no Discord
-- resource or bot is involved.

local LOG_META = {
    create = { title = "Graffiti created", color = 3066993 },
    delete = { title = "Graffiti deleted", color = 15158332 },
    erase  = { title = "Graffiti wiped",   color = 15105570 },
    admin  = { title = "Admin: graffiti",  color = 3447003 },
}

function Spray_log(kind, plr, g, extra)
    local meta = LOG_META[kind]
    if not meta then return end

    local who = isElement(plr) and getPlayerName(plr):gsub("#%x%x%x%x%x%x", "") or "unknown"
    local where = g and ("%.1f, %.1f, %.1f (dim %d, int %d)"):format(
        g.x, g.y, g.z, g.dimension or 0, g.interior or 0) or "-"

    outputServerLog(("[spraypaint] %s | player: %s | id: %s | pos: %s%s")
        :format(meta.title, who, tostring(g and g.id or "-"), where,
                extra and (" | " .. tostring(extra)) or ""))

    local hook = Config.DiscordWebhook
    if type(hook) ~= "string" or hook == "" then return end

    local fields = {
        { name = "Player", value = who, inline = true },
        { name = "ID",     value = tostring(g and g.id or "-"), inline = true },
    }
    if g then
        fields[#fields + 1] = { name = "Position", value = where, inline = false }
        if g.ownerName then
            fields[#fields + 1] = { name = "Author", value = tostring(g.ownerName), inline = true }
        end
    end
    if extra then
        fields[#fields + 1] = { name = "Detail", value = tostring(extra), inline = true }
    end

    fetchRemote(hook, {
        queueName = "spraypaint",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        postData = toJSON({
            embeds = { { title = meta.title, color = meta.color, fields = fields } },
        }, true),
        connectionAttempts = 1,
        connectionTimeout = 5000,
    }, function() end)
end

-- ─── Admin command ───────────────────────────────────────────────────────────

local function usage(plr)
    outputChatBox("#88ccff[Graffiti] #ffffffUsage:", plr, 255, 255, 255, true)
    outputChatBox("  /" .. Config.AdminCommand .. " list [radius]    - list graffiti nearby (with author)", plr, 200, 200, 200)
    outputChatBox("  /" .. Config.AdminCommand .. " authors          - toggle in-game author labels", plr, 200, 200, 200)
    outputChatBox("  /" .. Config.AdminCommand .. " delete <id>      - delete one graffiti", plr, 200, 200, 200)
    outputChatBox("  /" .. Config.AdminCommand .. " tp <id>          - teleport to a graffiti", plr, 200, 200, 200)
    outputChatBox("  /" .. Config.AdminCommand .. " clear <radius>   - delete everything nearby", plr, 200, 200, 200)
    outputChatBox("  /" .. Config.AdminCommand .. " player <id|name> - delete ALL graffiti of a player", plr, 200, 200, 200)
end

-- Author overlay (in-game labels) - who has it enabled.
local authorOverlay = {}   -- [admin] = true

-- Nearby graffiti for the overlay (id, position, author).
local function authorsNear(px, py, pz, radius)
    local out = {}
    for id, g in pairs(Spray_getAll()) do
        if Util.dist3D(px, py, pz, g.x, g.y, g.z) <= radius then
            out[#out + 1] = { id = id, x = g.x, y = g.y, z = g.z,
                              name = g.ownerName or "?" }
        end
    end
    return out
end

-- A client with the overlay on periodically asks for a fresh list.
addEvent("spraypaint:authorRefresh", true)
addEventHandler("spraypaint:authorRefresh", root, function()
    local plr = client
    if not isElement(plr) or not authorOverlay[plr] or not isAdmin(plr) then return end
    local px, py, pz = getElementPosition(plr)
    triggerClientEvent(plr, "spraypaint:authorOverlay", resourceRoot,
        authorsNear(px, py, pz, Config.AdminAuthorRadius or 80), true)
end)

addEventHandler("onPlayerQuit", root, function()
    authorOverlay[source] = nil
end)

addCommandHandler(Config.AdminCommand, function(plr, _, action, arg)
    if not isAdmin(plr) then
        return notify(plr, "You are not allowed to do that.", {255, 80, 80})
    end

    local all = Spray_getAll()
    local px, py, pz = getElementPosition(plr)

    if action == "list" then
        local radius = tonumber(arg) or 100.0
        local found = 0

        outputChatBox("#88ccff[Graffiti] #ffffffWithin " .. radius .. " m:", plr, 255, 255, 255, true)
        for id, g in pairs(all) do
            local d = Util.dist3D(px, py, pz, g.x, g.y, g.z)
            if d <= radius then
                found = found + 1
                outputChatBox(("  #%d  %.0f m  author: %s"):format(id, d, tostring(g.ownerName or "?")),
                              plr, 200, 200, 200)
            end
        end

        if found == 0 then
            outputChatBox("  (nothing found)", plr, 160, 160, 160)
        end
        return
    end

    if action == "delete" then
        local id = tonumber(arg)
        if not id then return usage(plr) end

        local ok, g = Spray_delete(id)
        if not ok then
            return notify(plr, "Graffiti #" .. id .. " does not exist.", {255, 150, 50})
        end

        notify(plr, "Graffiti #" .. id .. " deleted.", {80, 220, 100})
        if Config.LogDelete then Spray_log("admin", plr, g, "deleted #" .. id) end
        return
    end

    if action == "tp" then
        local id = tonumber(arg)
        local g = id and all[id]
        if not g then return notify(plr, "Graffiti #" .. tostring(arg) .. " does not exist.", {255, 150, 50}) end

        -- Put the player a bit in front of the wall, not inside it
        setElementDimension(plr, g.dimension or 0)
        setElementInterior(plr, g.interior or 0)
        setElementPosition(plr, g.x + g.nx * 2.0, g.y + g.ny * 2.0, g.z)
        notify(plr, "Teleported to graffiti #" .. id .. ".", {80, 220, 100})
        return
    end

    if action == "clear" then
        local radius = tonumber(arg)
        if not radius then return usage(plr) end

        local ids = {}
        for id, g in pairs(all) do
            if Util.dist3D(px, py, pz, g.x, g.y, g.z) <= radius then
                ids[#ids + 1] = id
            end
        end

        for _, id in ipairs(ids) do Spray_delete(id) end

        notify(plr, ("Deleted %d graffiti within %.0f m."):format(#ids, radius), {80, 220, 100})
        if Config.LogDelete and #ids > 0 then
            Spray_log("admin", plr, nil, ("bulk delete of %d (r=%.0f m)"):format(#ids, radius))
        end
        return
    end

    -- Toggle the in-game author labels for nearby graffiti.
    if action == "authors" then
        authorOverlay[plr] = not authorOverlay[plr]
        local on = authorOverlay[plr]
        local list = on and authorsNear(px, py, pz, Config.AdminAuthorRadius or 80) or {}
        triggerClientEvent(plr, "spraypaint:authorOverlay", resourceRoot, list, on)
        notify(plr, on and "Author labels on." or "Author labels off.", {120, 220, 255})
        return
    end

    -- Delete EVERY graffiti of a given player (by owner id or by name).
    if action == "player" then
        if not arg or arg == "" then return usage(plr) end
        local wanted = tostring(arg)
        local lname  = wanted:lower()

        local ids = {}
        for id, g in pairs(all) do
            local byId   = g.ownerId and tostring(g.ownerId):lower() == lname
            local byName = g.ownerName and tostring(g.ownerName):lower():find(lname, 1, true)
            if byId or byName then ids[#ids + 1] = id end
        end

        for _, id in ipairs(ids) do Spray_delete(id) end

        notify(plr, ("Deleted %d graffiti of '%s'."):format(#ids, wanted),
               #ids > 0 and {80, 220, 100} or {255, 150, 50})
        if Config.LogDelete and #ids > 0 then
            Spray_log("admin", plr, nil, ("bulk delete of %d from '%s'"):format(#ids, wanted))
        end
        return
    end

    usage(plr)
end)
