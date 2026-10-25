--[[
    spraypaint - built-in notification popup (client side).

    Replaces the external notification resource this script originally used.
    A small stack of boxes in the top right corner, each fading out on its own.
    Nothing else depends on how it looks, so restyle it freely.

    Notify(title, text, color)  -- color = {r, g, b}, optional
]]--

local sx, sy = guiGetScreenSize()

local LIFETIME = 4500      -- how long a message stays on screen (ms)
local FADE     = 400       -- fade in / fade out length (ms)
local WIDTH    = 310
local HEIGHT   = 60
local MARGIN   = 14
local MAX      = 4

local queue = {}
local rendering = false

local function render()
    local now = getTickCount()
    local y = MARGIN

    for i = #queue, 1, -1 do
        local n = queue[i]
        local age = now - n.at

        if age > LIFETIME then
            table.remove(queue, i)
        else
            local alpha = 1
            if age < FADE then
                alpha = age / FADE
            elseif age > LIFETIME - FADE then
                alpha = (LIFETIME - age) / FADE
            end

            local x = sx - WIDTH - MARGIN
            local a = math.floor(alpha * 255)
            local r, g, b = n.color[1], n.color[2], n.color[3]

            dxDrawRectangle(x, y, WIDTH, HEIGHT, tocolor(0, 0, 0, math.floor(alpha * 190)))
            dxDrawRectangle(x, y, 4, HEIGHT, tocolor(r, g, b, a))
            dxDrawText(n.title, x + 14, y + 8, x + WIDTH - 10, y + 8,
                tocolor(r, g, b, a), 1.0, "default-bold")
            dxDrawText(n.text, x + 14, y + 26, x + WIDTH - 10, y + HEIGHT - 6,
                tocolor(255, 255, 255, a), 1.0, "default", "left", "top", true, true)

            y = y + HEIGHT + 8
        end
    end

    if #queue == 0 then
        removeEventHandler("onClientRender", root, render)
        rendering = false
    end
end

function Notify(title, text, color)
    if type(text) ~= "string" or text == "" then return end

    queue[#queue + 1] = {
        title = tostring(title or "Spray"),
        text  = text,
        color = (type(color) == "table" and #color >= 3) and color or { 120, 220, 255 },
        at    = getTickCount(),
    }
    while #queue > MAX do table.remove(queue, 1) end

    if not rendering then
        addEventHandler("onClientRender", root, render)
        rendering = true
    end
end

addEvent("spraypaint:notify", true)
addEventHandler("spraypaint:notify", root, function(title, text, color)
    Notify(title, text, color)
end)
