--[[
    spraypaint - integration layer (server side).

    The only file you need to touch to plug the resource into your own
    inventory, admin system or logging. Everything has a working standalone
    default, so the resource runs on a bare server as-is.
]]--

Integration = {}

-- ─── Items ───────────────────────────────────────────────────────────────────

-- How many pieces of `item` the player owns.
-- Only consulted when Config.RequireItems is true.
function Integration.countItem(plr, item)
    -- Example with an inventory resource:
    --   return tonumber(exports["my-inventory"]:countPlayerItem(plr, item)) or 0
    return 1
end

-- Take `count` pieces of `item` away from the player.
function Integration.takeItem(plr, item, count)
    -- Example with an inventory resource:
    --   exports["my-inventory"]:takePlayerItem(plr, item, count)
    return true
end

-- ─── Identity ────────────────────────────────────────────────────────────────

-- Stable owner id stored with the graffiti, used by /sprayadmin player <id>.
-- The account name is a reasonable default; swap it for your character id.
function Integration.getOwnerId(plr)
    local acc = getPlayerAccount(plr)
    if acc and not isGuestAccount(acc) then
        return getAccountName(acc)
    end
    return nil
end

-- ─── Admin ───────────────────────────────────────────────────────────────────

-- Who may use /sprayadmin. By default the ACL right from Config.AdminRight.
function Integration.isAdmin(plr)
    if not isElement(plr) then return false end
    return hasObjectPermissionTo(plr, Config.AdminRight or "command.kick", false)
end

-- ─── Notifications ───────────────────────────────────────────────────────────

-- Shown to the player. `color` is {r, g, b}.
function Integration.notify(plr, title, text, color)
    if not isElement(plr) then return end
    triggerClientEvent(plr, "spraypaint:notify", plr, title, text, color)
end

-- ─── Hooks ───────────────────────────────────────────────────────────────────

-- Called after a player wipes a graffiti off with the cloth. Handy for paying
-- out a cleaning job, counting a task, etc. Empty by default.
function Integration.onGraffitiErased(plr, g)
end
