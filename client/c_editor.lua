--[[
    spraypaint - the drawing editor

    Once a surface is selected, a 2D canvas opens and the player draws the
    graffiti with the mouse. The strokes use the same format and the same
    drawing code as a graffiti on a wall (c_canvas.lua), so the preview in the
    editor matches the result.

    The editor canvas is however created WITHOUT the texture orientation
    compensation - that belongs to the wall only. Otherwise the player would be
    drawing mirrored against what they see.
]]--

Editor = {}

local sw, sh = guiGetScreenSize()

local open        = false
local strokes     = nil
local canvas      = nil
local colorIndex  = Config.DefaultColor
local brushIndex  = Config.DefaultBrush
local lockedColor = nil

-- pressActive: the button is held and the press started inside the canvas
-- strokeOpen:  points are currently being appended to an open stroke
local pressActive = false
local strokeOpen  = false
local lastU, lastV = nil, nil

local onConfirmCb, onCancelCb = nil, nil

-- Running point counter. This used to be computed by walking every stroke on
-- EVERY added point - on large drawings that meant tens of millions of
-- operations and the editor stuttered noticeably.
local pointCount = 0

-- ─── Layout ──────────────────────────────────────────────────────────────────

local L = {}

local function computeLayout()
    local size = math.min(sw * 0.46, sh * 0.62)

    L.canvasSize = size
    L.canvasX    = (sw - size) / 2
    L.canvasY    = sh * 0.10

    L.swatch     = math.min(38, size / 12)
    L.paletteY   = L.canvasY + size + 18
    L.paletteW   = #Config.Colors * L.swatch + (#Config.Colors - 1) * 6
    L.paletteX   = (sw - L.paletteW) / 2

    L.brushY     = L.paletteY + L.swatch + 14
    L.brushW     = 110
    L.brushGap   = 8
    L.brushTotal = #Config.BrushSizes * L.brushW + (#Config.BrushSizes - 1) * L.brushGap
    L.brushX     = (sw - L.brushTotal) / 2

    L.btnY       = L.brushY + 44
    L.btnW       = 150
    L.btnH       = 40
    L.btnGap     = 10
end

local function inRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

-- The buttons are generated in one place so drawing and clicking use literally
-- the same rectangles and cannot drift apart.
local function getButtons()
    local n = 4
    local total = n * L.btnW + (n - 1) * L.btnGap
    local x = (sw - total) / 2

    local defs = {
        { id = "confirm", label = "Spray it",    col = { 60, 170,  80} },
        { id = "undo",    label = "Undo (Z)",    col = { 70,  90, 120} },
        { id = "clear",   label = "Clear all",   col = {120,  90,  50} },
        { id = "cancel",  label = "Cancel",      col = {150,  60,  60} },
    }

    for i, b in ipairs(defs) do
        b.x, b.y, b.w, b.h = x + (i - 1) * (L.btnW + L.btnGap), L.btnY, L.btnW, L.btnH
    end
    return defs
end

-- ─── Open and close ──────────────────────────────────────────────────────────

function Editor.open(forcedColor, confirmCb, cancelCb)
    if open then return false end

    computeLayout()

    strokes     = {}
    canvas      = Canvas.new(strokes, false)
    if not canvas then return false end

    open        = true
    lockedColor = forcedColor
    colorIndex  = forcedColor or Config.DefaultColor
    brushIndex  = Config.DefaultBrush
    pressActive = false
    strokeOpen  = false
    pointCount  = 0
    lastU, lastV = nil, nil
    onConfirmCb, onCancelCb = confirmCb, cancelCb

    showCursor(true)
    bindKey(Config.Keys.Undo, "down", Editor.undo)
    for i = 1, math.min(9, #Config.Colors) do
        bindKey(tostring(i), "down", Editor.onColorKey)
    end
    if #Config.Colors >= 10 then bindKey("0", "down", Editor.onColorKey) end

    return true
end

function Editor.close()
    if not open then return end

    if canvas then
        Canvas.destroy(canvas)
        canvas = nil
    end

    open        = false
    strokes     = nil
    pressActive = false
    strokeOpen  = false
    onConfirmCb, onCancelCb = nil, nil

    showCursor(false)
    unbindKey(Config.Keys.Undo, "down", Editor.undo)
    for i = 1, math.min(9, #Config.Colors) do
        unbindKey(tostring(i), "down", Editor.onColorKey)
    end
    unbindKey("0", "down", Editor.onColorKey)
end

function Editor.isOpen() return open end

-- ─── Strokes ─────────────────────────────────────────────────────────────────

-- Cursor position -> canvas coordinates 0..1, or nil outside the surface.
local function cursorToUV()
    local cx, cy = getCursorPosition()
    if not cx then return nil end
    cx, cy = cx * sw, cy * sh

    if not inRect(cx, cy, L.canvasX, L.canvasY, L.canvasSize, L.canvasSize) then
        return nil
    end

    return (cx - L.canvasX) / L.canvasSize, (cy - L.canvasY) / L.canvasSize
end

local function canvasFull()
    Notify("Spray", "The canvas is full, nothing more fits on it.", {255, 150, 50})
    pressActive, strokeOpen = false, false
end

local function beginStroke(u, v)
    if #strokes >= Config.MaxStrokes or pointCount >= Config.MaxTotalPoints then
        canvasFull()
        return false
    end
    strokes[#strokes + 1] = { c = colorIndex, b = brushIndex, p = { u, v } }
    pointCount = pointCount + 1
    lastU, lastV = u, v
    return true
end

local function addPoint(u, v)
    local s = strokes[#strokes]
    if not s then return end

    if pointCount >= Config.MaxTotalPoints then
        return canvasFull()
    end

    -- Points practically on top of each other only inflate the data
    if lastU then
        local du, dv = u - lastU, v - lastV
        local min = Config.MinPointDistance
        if (du*du + dv*dv) < (min * min) then return end
    end

    -- The stroke hit its point limit: close it and continue seamlessly with a
    -- new one anchored to the last point. Points used to be silently dropped
    -- instead, so part of a long continuous stroke was simply missing.
    if #s.p / 2 >= Config.MaxPointsPerStroke then
        if #strokes >= Config.MaxStrokes then
            return canvasFull()
        end
        strokes[#strokes + 1] = { c = s.c, b = s.b, p = { lastU, lastV } }
        pointCount = pointCount + 1
        s = strokes[#strokes]
    end

    -- The length has to be stored BEFORE writing. If #s.p were evaluated a
    -- second time after the first assignment it would already be one higher
    -- and the second coordinate would land one index further - leaving a hole,
    -- an odd-length array and unpaired u/v (the stroke would run off somewhere
    -- entirely different).
    local n = #s.p
    s.p[n + 1] = u
    s.p[n + 2] = v
    pointCount = pointCount + 1
    lastU, lastV = u, v
end

-- ─── Actions ─────────────────────────────────────────────────────────────────

function Editor.undo()
    if not open or strokeOpen then return end
    if #strokes == 0 then return end

    pointCount = pointCount - #strokes[#strokes].p / 2
    strokes[#strokes] = nil
    Canvas.markDirty(canvas)
end

function Editor.clear()
    if not open then return end
    for i = #strokes, 1, -1 do strokes[i] = nil end
    pointCount = 0
    Canvas.markDirty(canvas)
end

function Editor.onColorKey(key)
    if not open then return end
    if lockedColor then
        return Notify("Spray", "This spray can has a fixed color.", {255, 150, 50})
    end
    local idx = (key == "0") and 10 or tonumber(key)
    if idx and Config.Colors[idx] then colorIndex = idx end
end

local function confirm()
    -- Empty strokes must not be sent, the server would reject the whole canvas
    local filtered = {}
    for i = 1, #strokes do
        if #strokes[i].p >= 2 then filtered[#filtered + 1] = strokes[i] end
    end

    if #filtered == 0 then
        return Notify("Spray", "The canvas is empty.", {255, 150, 50})
    end

    -- The drawing goes through the SAME check the server will use. If it were
    -- only verified after sending, the player would watch the whole spraying
    -- animation and only then find out the graffiti will not be saved.
    local clean, err = Util.validateStrokes(filtered)
    if not clean then
        return Notify("Spray",
            "This drawing cannot be sprayed: " .. err .. ". Simplify it or erase something.",
            {255, 80, 80})
    end

    local cb = onConfirmCb
    Editor.close()
    if cb then cb(clean) end
end

local function cancel()
    local cb = onCancelCb
    Editor.close()
    if cb then cb() end
end

-- ─── Input ───────────────────────────────────────────────────────────────────

addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if not open or button ~= "left" then return end

    if state == "up" then
        pressActive, strokeOpen = false, false
        lastU, lastV = nil, nil
        return
    end

    -- Buttons
    for _, b in ipairs(getButtons()) do
        if inRect(absX, absY, b.x, b.y, b.w, b.h) then
            if     b.id == "confirm" then confirm()
            elseif b.id == "cancel"  then cancel()
            elseif b.id == "undo"    then Editor.undo()
            elseif b.id == "clear"   then Editor.clear() end
            return
        end
    end

    -- Palette
    if not lockedColor then
        for i = 1, #Config.Colors do
            local bx = L.paletteX + (i - 1) * (L.swatch + 6)
            if inRect(absX, absY, bx, L.paletteY, L.swatch, L.swatch) then
                colorIndex = i
                return
            end
        end
    end

    -- Brush size
    for i = 1, #Config.BrushSizes do
        local bx = L.brushX + (i - 1) * (L.brushW + L.brushGap)
        if inRect(absX, absY, bx, L.brushY, L.brushW, 32) then
            brushIndex = i
            return
        end
    end

    -- A stroke may only start inside the drawing area, so clicking a button or
    -- outside the panel leaves no line. The points themselves are collected by
    -- the render loop.
    if cursorToUV() then
        pressActive = true
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not open or not press then return end

    -- onClientKey fires while typing in the chat too, unlike bindKey. Without
    -- this guard, Enter sent to the chat would immediately spray the drawing.
    if isChatBoxInputActive() or isConsoleActive() then return end

    if key == Config.Keys.BrushUp then
        brushIndex = math.min(#Config.BrushSizes, brushIndex + 1)
    elseif key == Config.Keys.BrushDown then
        brushIndex = math.max(1, brushIndex - 1)
    elseif key == Config.Keys.Confirm then
        confirm()
    elseif key == Config.Keys.Cancel then
        cancel()
    end
end)

-- ─── Drawing the panel ───────────────────────────────────────────────────────

local function drawPanel()
    -- Dim the background so the drawing area is readable
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 170), false)

    dxDrawText("GRAFFITI DESIGN", 0, L.canvasY - 46, sw, L.canvasY - 46,
               tocolor(255, 255, 255, 235), 1.4, "default-bold", "center", "top")
    dxDrawText("Draw with the mouse inside the frame  •  wheel = brush size  •  Z = undo",
               0, L.canvasY - 22, sw, L.canvasY - 22,
               tocolor(190, 190, 190, 210), 0.95, "default", "center", "top")

    -- Drawing area
    local x, y, s = L.canvasX, L.canvasY, L.canvasSize
    dxDrawRectangle(x - 2, y - 2, s + 4, s + 4, tocolor(255, 255, 255, 90))
    dxDrawRectangle(x, y, s, s, tocolor(235, 235, 235, 245))
    dxDrawImage(x, y, s, s, canvas.rt)

    -- Palette
    for i, c in ipairs(Config.Colors) do
        local bx = L.paletteX + (i - 1) * (L.swatch + 6)
        if i == colorIndex then
            dxDrawRectangle(bx - 3, L.paletteY - 3, L.swatch + 6, L.swatch + 6, tocolor(255, 255, 255, 240))
        end
        local a = lockedColor and (i == colorIndex and 255 or 70) or 255
        dxDrawRectangle(bx, L.paletteY, L.swatch, L.swatch, tocolor(c.rgb[1], c.rgb[2], c.rgb[3], a))
    end

    -- Brushes
    for i, b in ipairs(Config.BrushSizes) do
        local bx = L.brushX + (i - 1) * (L.brushW + L.brushGap)
        local sel = (i == brushIndex)
        dxDrawRectangle(bx, L.brushY, L.brushW, 32, tocolor(sel and 90 or 40, sel and 110 or 40, sel and 150 or 40, 220))
        dxDrawText(b.name, bx, L.brushY, bx + L.brushW, L.brushY + 32,
                   tocolor(255, 255, 255, sel and 255 or 170), 0.95, "default-bold", "center", "center")
    end

    -- Buttons
    for _, b in ipairs(getButtons()) do
        dxDrawRectangle(b.x, b.y, b.w, b.h, tocolor(b.col[1], b.col[2], b.col[3], 235))
        dxDrawText(b.label, b.x, b.y, b.x + b.w, b.y + b.h,
                   tocolor(255, 255, 255, 255), 1.0, "default-bold", "center", "center")
    end

    -- Canvas usage. The limit is on points, not strokes, so that is what gets
    -- shown - otherwise the player has no way to tell they are near the cap.
    local fill = pointCount / Config.MaxTotalPoints
    local warn = fill >= 0.8
    dxDrawText(("Used: %d %%"):format(math.floor(fill * 100 + 0.5)),
               0, L.btnY + L.btnH + 10, sw, L.btnY + L.btnH + 10,
               warn and tocolor(255, 170, 60, 230) or tocolor(160, 160, 160, 200),
               0.85, "default", "center", "top")
end

addEventHandler("onClientRender", root, function()
    if not open then return end

    -- Collecting the stroke points.
    --
    -- The button state is read directly through getKeyState, not only from
    -- onClientClick. If the release event is lost (window switch, click
    -- outside the game), drawing would continue without the button held.
    if pressActive then
        if not getKeyState("mouse1") then
            pressActive, strokeOpen = false, false
            lastU, lastV = nil, nil
        else
            local u, v = cursorToUV()
            if u then
                if strokeOpen then
                    addPoint(u, v)
                elseif beginStroke(u, v) then
                    strokeOpen = true
                end
            elseif strokeOpen then
                -- The cursor left the canvas: close the stroke. Coming back
                -- starts a new one, otherwise a straight line would join them
                -- across the whole canvas.
                strokeOpen = false
                lastU, lastV = nil, nil
            end
        end
    end

    Canvas.flush(canvas)
    drawPanel()
end)
