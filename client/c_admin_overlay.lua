--[[
    spraypaint - client: in-game author labels for graffiti (admins only).

    Through /sprayadmin authors the server sends a list of
    { id, x, y, z, name } for the graffiti nearby plus an on/off flag. While the
    overlay is on, the client periodically asks for a fresh list and draws
    "#id  author" above every graffiti.
]]--

local enabled = false
local list    = {}
local refreshTimer = nil

local MAX_LABEL_DIST = 60   -- m: no labels beyond this

addEvent("spraypaint:authorOverlay", true)
addEventHandler("spraypaint:authorOverlay", resourceRoot, function(data, on)
    list    = (type(data) == "table") and data or {}
    enabled = on and true or false

    if enabled then
        if not refreshTimer then
            refreshTimer = setTimer(function()
                triggerServerEvent("spraypaint:authorRefresh", localPlayer)
            end, 3000, 0)
        end
    else
        if refreshTimer then killTimer(refreshTimer); refreshTimer = nil end
    end
end)

addEventHandler("onClientRender", root, function()
    if not enabled or #list == 0 then return end
    local px, py, pz = getElementPosition(localPlayer)

    for _, g in ipairs(list) do
        local dx, dy, dz = g.x - px, g.y - py, g.z - pz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist <= MAX_LABEL_DIST then
            local sx, sy = getScreenFromWorldPosition(g.x, g.y, g.z + 0.9, 0.5)
            if sx then
                local txt = ("#%d  %s"):format(g.id, tostring(g.name or "?"))
                dxDrawText(txt, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 210), 1, nil, "center", "center")
                dxDrawText(txt, sx, sy, sx, sy, tocolor(120, 220, 255, 255), 1, nil, "center", "center")
            end
        end
    end
end)
