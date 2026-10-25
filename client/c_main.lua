--[[
    spraypaint - client entry points

    The client never allows itself to spray - it always asks the server, which
    verifies the item. Otherwise calling one event from a cheat would be enough.
]]--

local function requestPaint()
    if Paint.getMode() or Eraser.isActive() then return end
    triggerServerEvent("spraypaint:request", localPlayer)
end

local function requestErase()
    if Paint.getMode() or Eraser.isActive() then return end
    triggerServerEvent("spraypaint:requestErase", localPlayer)
end

if Config.UseCommand then
    addCommandHandler(Config.Command, requestPaint)
    addCommandHandler(Config.EraseCommand, requestErase)
end

-- Public events for an inventory: trigger these when the item is used.
addEvent("spraypaint:itemUse", true)
addEventHandler("spraypaint:itemUse", root, requestPaint)

addEvent("spraypaint:clothUse", true)
addEventHandler("spraypaint:clothUse", root, requestErase)

-- ─── Streaming ───────────────────────────────────────────────────────────────

local function requestSync()
    triggerServerEvent("spraypaint:requestSync", localPlayer)
end

addEventHandler("onClientResourceStart", resourceRoot, requestSync)
addEventHandler("onClientPlayerSpawn", localPlayer, requestSync)

-- The server sends graffiti based on where the player is, so the sync repeats
-- as they move around
setTimer(requestSync, 15000, 0)

-- ─── Cleanup ─────────────────────────────────────────────────────────────────

addEventHandler("onClientResourceStop", resourceRoot, function()
    Paint.stop(true)
    Eraser.stop(true)
end)

-- Dying mid-spray would leave the player with blocked controls
addEventHandler("onClientPlayerWasted", localPlayer, function()
    Paint.stop(true)
    Eraser.stop(true)
end)
